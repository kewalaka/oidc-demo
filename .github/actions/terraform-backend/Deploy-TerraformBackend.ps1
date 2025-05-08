param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string]$StateContainerName,

    [Parameter(Mandatory=$true)]
    [string]$ArtifactContainerName
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'
$storageSKU = 'Standard_LRS' # Or consider Standard_GRS for production
$tags = @{ Purpose = "Terraform Backend" }

# Helper function for RBAC assignment
function Grant-RBACRole {
    param(
        [string]$PrincipalId,
        [string]$Scope,
        [string]$RoleDefinitionName
    )
    $assignment = Get-AzRoleAssignment -ObjectId $PrincipalId -Scope $Scope -RoleDefinitionName $RoleDefinitionName -ErrorAction SilentlyContinue
    if ($null -eq $assignment) {
        Write-Host "Granting role '$RoleDefinitionName' to Principal '$PrincipalId' at scope '$Scope'"
        New-AzRoleAssignment -ObjectId $PrincipalId -Scope $Scope -RoleDefinitionName $RoleDefinitionName
    } else {
        Write-Host "Role '$RoleDefinitionName' already exists for Principal '$PrincipalId' at scope '$Scope'"
    }
}

Import-Module Az.Storage, Az.Resources | Out-Null

Write-Host "Ensuring Terraform backend storage exists..."
Write-Host "Deploying Identity Client ID: $env:ARM_CLIENT_ID" # Environment variables are accessible

$deployPrincipalId = $env:ARM_CLIENT_ID.Trim()

# Verify Resource Group exists and get location
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $rg) {
    Write-Error "Resource Group '$ResourceGroupName' does not exist or is not accessible. It must exist before running this action."
    exit 1
}
$Location = $rg.Location
Write-Host "Using existing Resource Group '$ResourceGroupName' in location '$Location'."

# Ensure Storage Account (check name availability first)
$nameCheck = Get-AzStorageAccountNameAvailability -Name $StorageAccountName
if (-not $nameCheck.NameAvailable) {
    $saCheck = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
    if ($null -eq $saCheck) {
        Write-Error "Storage account name '$StorageAccountName' is unavailable. Reason: $($nameCheck.Message)"
        exit 1
    }
    Write-Host "Storage Account '$StorageAccountName' already exists. Verifying settings..."
    $sa = $saCheck
    # Temporarily enable shared key access if it exists but is disabled
    if ($sa.AllowSharedKeyAccess -eq $false) {
        Write-Host "Temporarily enabling shared key access on existing account '$StorageAccountName' for setup."
        Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -AllowSharedKeyAccess $true | Out-Null
    }
} else {
    Write-Host "Creating Storage Account: '$StorageAccountName' in location '$Location'"
    $saParams = @{
        ResourceGroupName      = $ResourceGroupName
        Name                   = $StorageAccountName
        Location               = $Location # Use location from existing RG
        SkuName                = $storageSKU
        Kind                   = 'StorageV2'
        AccessTier             = 'Hot'
        EnableHttpsTrafficOnly = $true
        EnableLocalUser        = $false
        AllowBlobPublicAccess  = $false
        AllowSharedKeyAccess   = $true  # Enable temporarily for container creation
        MinimumTlsVersion      = 'TLS1_2'
        Tag                    = $tags
    }
    $sa = New-AzStorageAccount @saParams
}

# Configure Blob Service Properties (Versioning, Retention)
Write-Host "Configuring Blob Service properties for '$StorageAccountName' (Versioning, Retention)"
Update-AzStorageBlobServiceProperty -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -IsVersioningEnabled $true -EnableChangeFeed $false | Out-Null
Enable-AzStorageBlobDeleteRetentionPolicy -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -RetentionDays 7 -AllowPermanentDelete:$false | Out-Null

# Get Storage Context using Account Key (needed for initial container creation)
$accountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $accountKey

# Ensure State Container
$stateContainer = Get-AzStorageContainer -Context $ctx -Name $StateContainerName -ErrorAction SilentlyContinue
if ($null -eq $stateContainer) {
    Write-Host "Creating State Container: '$StateContainerName'"
    New-AzStorageContainer -Name $StateContainerName -Context $ctx
} else {
    Write-Host "State Container '$StateContainerName' already exists."
}
$stateContainerScope = "$($sa.Id)/blobServices/default/containers/$StateContainerName"

# Ensure Artifact Container
$artifactContainer = Get-AzStorageContainer -Context $ctx -Name $ArtifactContainerName -ErrorAction SilentlyContinue
if ($null -eq $artifactContainer) {
    Write-Host "Creating Artifact Container: '$ArtifactContainerName'"
    New-AzStorageContainer -Name $ArtifactContainerName -Context $ctx
} else {
    Write-Host "Artifact Container '$ArtifactContainerName' already exists."
}
$artifactContainerScope = "$($sa.Id)/blobServices/default/containers/$ArtifactContainerName"

# Grant RBAC on Containers to deploying identity (Mandatory)
Write-Host "Granting mandatory container RBAC roles..."
Grant-RBACRole -PrincipalId $deployPrincipalId -Scope $stateContainerScope -RoleDefinitionName 'Storage Blob Data Contributor'
Grant-RBACRole -PrincipalId $deployPrincipalId -Scope $artifactContainerScope -RoleDefinitionName 'Storage Blob Data Contributor'

# Disable Shared Key Access now that setup is complete
Write-Host "Disabling shared key access on storage account '$StorageAccountName'."
Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -AllowSharedKeyAccess $false | Out-Null

Write-Host "Backend storage and RBAC verified successfully."