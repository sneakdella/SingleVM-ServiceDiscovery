<# Notes

- For use with vRealize Operations 8.10 Only (On-prem)
- If you change either Powershell Module file, make sure to Remove-Module Get-VMsWithTelegrafInstalled OR Remove-Module Add-WindowsOSServices
    via powershell before running again.
- By Default Add-WindowsOSServices will NOT commit the services unless you specify "-Commit $true"
#>


<#
    ############################## START OF CONFIG ##############################
#>

Import-Module ".\Get-VMsWithTelegrafInstalled.psm1"
Import-Module ".\Add-WindowsOSServices.psm1"

$RemoteCollector = "10.0.0.27"
$Credential = Get-Credential -Message "Please provide your vROps Credentials"

<# 
    ############################### END OF CONFIG ###############################
#>

<# ############################### BEGIN SCRIPT ############################### #>

$WinOSObjects = Get-VMsWithTelegrafInstalled -RemoteCollector $RemoteCollector -Credential $Credential

ForEach ($WinOSObj in $WinOSObjects.GetEnumerator()) {
    Add-WindowsOSServices -WindowsObjectUUID $WinOSObj.value -Credential $Credential -RemoteCollector $RemoteCollector -Commit $false 
}

<# ############################### END SCRIPT ############################# #>