function Get-VMsWithTelegrafInstalled {
    param (
        [Parameter(Mandatory=$true)]$RemoteCollector,
        [Parameter(Mandatory=$true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory=$false)]$AuthSource="LOCAL"
    )    

    ######## HEADER FOR API CALLS ##############
    $global:Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $global:Headers.Add("Content-Type", "application/json")
    $global:Headers.Add("Accept", "application/json")
    $global:accesstoken = ''
    ######## END HEADER FOR API CALLS ##########

    if ($AuthSource -eq "") {
        $AuthSource = "LOCAL"
    }

    # Gets the access token based on credentials.
    function Get-vROpsAccessToken {
        param (
            [Parameter(Mandatory=$true)]$RemoteCollector,
            [Parameter(Mandatory=$true)][System.Management.Automation.PSCredential]$Credential,
            [Parameter(Mandatory=$false)]$AuthSource="LOCAL",
            [Parameter(Mandatory=$false)]$Refresh=$false,
            [Parameter(Mandatory=$false)]$FunctionDebug=$false
        )

        #Write-Host $Credential.GetNetworkCredential().Password

        $jsonBody = @{
            "username"=$Credential.UserName;
            "authSource"=$AuthSource;
            "password"=$Credential.GetNetworkCredential().Password;
        } | ConvertTo-JSON
        
        If ($Refresh -eq $false) {
            $global:accesstoken = Invoke-RestMethod "https://$RemoteCollector/suite-api/api/auth/token/acquire?_no_links=true" -Method 'POST' -Headers $Headers -Body $jsonBody -SkipCertificateCheck
        } elseif ($Refresh -eq $true) {
            $global:Headers.Remove("Authorization")
            $global:accesstoken = Invoke-RestMethod "https://$RemoteCollector/suite-api/api/auth/token/acquire?_no_links=true" -Method 'POST' -Headers $Headers -Body $jsonBody -SkipCertificateCheck
        }

        # Clear authentication from memory
        $jsonBody = ""
        
        # DEBUG: Show $accesstoken
        If ($FunctionDebug -eq $true){
            Write-Host "function Get-vROpsAccessToken | `$accesstoken DEBUG:" $accesstoken
        }
        
        $global:Headers.Add("Authorization", "vRealizeOpsToken " +$global:accesstoken.token)
    }

    # Gets all the Windows OS objects
    function Get-AllWindowsOSObjects {
        
        param (
            [Parameter(Mandatory=$true)]$RemoteCollector,
            [Parameter(Mandatory=$true)]$Headers,
            [Parameter(Mandatory=$false)]$FunctionDebug=$false
        )

        $AllWindowsOSObjects = Invoke-RestMethod "https://$RemoteCollector/suite-api/api/resources?adapterKind=APPOSUCP&page=0&pageSize=1000&resourceKind=win&resourceState=&resourceStatus=&_no_links=true" -Method 'GET' -Headers $Headers -SkipCertificateCheck

        return $AllWindowsOSObjects
    }

    # Takes json response from Get-AllWindowsOSObjects and converts it to a hashtable.
    function Optimize-ListOfWindowsOSObjects {

        param(
            [Parameter(Mandatory=$true)]$AllWindowsOSObjects
        )

        $AllWindowsOSObjects = $AllWindowsOSObjects.resourceList
        $WinOSObjectsHashTable = @{}

        ForEach ($WinObj in $AllWindowsOSObjects) {
            #DEBUG Write-Host $WinObj.resourceKey.name $WinObj.identifier
            $WinOSObjectsHashTable.Add($WinObj.resourceKey.name, $WinObj.identifier)
        }

        return $WinOSObjectsHashTable
    }

    Get-vROpsAccessToken -RemoteCollector $RemoteCollector -Credential $Credential -AuthSource $AuthSource #-FunctionDebug $true
    $AllWindowsOSObjects = Get-AllWindowsOSObjects -RemoteCollector $RemoteCollector -Headers $Headers
    $WinOSObjectHashTable = Optimize-ListOfWindowsOSObjects -AllWindowsOSObjects $AllWindowsOSObjects

    return $WinOSObjectHashTable
}