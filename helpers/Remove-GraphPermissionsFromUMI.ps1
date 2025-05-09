$permsToRemove  = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $umiSP.Id

foreach ($perm in $permsToRemove){
  Remove-MgServicePrincipalAppRoleAssignment `
   -AppRoleAssignmentId $perm.id `
   -ServicePrincipalId $umiSP.Id
}