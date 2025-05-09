# Set parameters
$TenantId = $env:ARM_TENANT_ID
$ManagedIdentityName = "mi-oidc-demo-dev"
$PermissionsToGrantToMI = @(
  "Group.ReadWrite.All",
  "User.Read.All"
)
# end params


Connect-MgGraph `
  -Scopes @("Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All") `
  -TenantId $TenantId

$MSGraphAPIResourceId = "00000003-0000-0000-c000-000000000000" # This is the well-known resource ID for the MS Graph

$graphSP = Get-MgServicePrincipal -Filter "AppId eq '$MSGraphAPIResourceId'"
$permissions = $graphSP.AppRoles | Where-Object { $_.Value -in $PermissionsToGrantToMI }
$umiSP = Get-MgServicePrincipal -Filter "DisplayName eq '$ManagedIdentityName'" 

foreach ($perm in $permissions) {
  New-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId $umiSP.Id `
    -PrincipalId $umiSP.Id `
    -ResourceId $graphSP.Id `
    -AppRoleId $perm.Id
}