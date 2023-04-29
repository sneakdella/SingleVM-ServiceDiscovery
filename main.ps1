######## HEADER FOR API CALLS ##############
$global:Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$global:Headers.Add("Content-Type", "application/json")
$global:Headers.Add("Accept", "application/json")
$global:accesstoken = ''
######## END HEADER FOR API CALLS ##########

$RemoteCollector = "10.0.0.27"
$Credential = Get-Credential -Message "Please provide your vROps Credentials"
$AuthSource = Read-Host "Enter the auth source of the account. [Leave blank if LOCAL]"

if ($AuthSource -eq "") {
    $AuthSource = "LOCAL"
}

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

function Get-WindowsOSObjServicesStats {
    param (
        [Parameter(Mandatory=$true)]$RemoteCollector,
        [Parameter(Mandatory=$true)]$Headers,
        [Parameter(Mandatory=$false)]$FunctionDebug=$false
    )

    $WindowsOSObjectServicesStats = Invoke-RestMethod "https://$RemoteCollector/suite-api/api/resources/961ab153-7fd6-4a34-9d9a-b317014f5686/stats/latest?currentOnly=false&_no_links=true" -Method 'GET' -Headers $Headers -SkipCertificateCheck

    $StatList = $WindowsOSObjectServicesStats.values."stat-list"."stat"
    
    $FinalOutput = @{}

    ForEach ($stat in $StatList) {
        If (($stat.statKey -match "startup.mode") -and ($stat.data -eq "3")) {
            Write-Host $stat.statKey $stat.data
        }
    }

    return $WindowsOSObjectServicesStats
}

# Get specific Windows OS object's service objects properties
function Get-WindowsOSObjProperties {
    param (
        [Parameter(Mandatory=$true)]$RemoteCollector,
        [Parameter(Mandatory=$true)]$Headers,
        [Parameter(Mandatory=$false)]$FunctionDebug=$false
    )

    $WindowsOSObjectProperties = Invoke-RestMethod "https://$RemoteCollector/suite-api/api/resources/961ab153-7fd6-4a34-9d9a-b317014f5686/properties?_no_links=true" -Method 'GET' -Headers $Headers -SkipCertificateCheck

    return $WindowsOSObjectProperties
}

# Find anything starting with "Tags:services|"
# Grab the Service Display Name between the first | and second |
# Output dictionary with value

function Get-ExactServiceNameByTag {
    param (
        [Parameter(Mandatory=$true)]$WindowsOSObjectProperties
    )

    $hashtable = @{}
    ForEach ($property in $WindowsOSObjectProperties.property) {
        If ($property.name.StartsWith("Tags:services|")) {
            $ServiceDisplayName = $property.name.split("|")[1]
            $hashtable.add($ServiceDisplayName, $property.value)
        }
    }

    return $hashtable
}

# Finds and removes blacklisted services from the hashtable.
function Find-BlackListedServices {
    param (
        [Parameter(Mandatory=$true)]$ExactServices
    )

    try {
        $BlackListedServices = $(Import-CSV .\BlackList.csv).ServiceName
    }
    catch {
        Write-Error "UNABLE TO OPEN BLACKLIST.CSV"
    }
    Write-Host $ExactServices
    $FinalServices = @{}

    ForEach ($Service in $ExactServices.GetEnumerator()) {

        $SkipService = $False

        ForEach ($BLService in $BlackListedServices) {
            If ($Service.key -match $BLService) {
                Write-Host "SKIPPED: " $Service "|||||" $BLService
                $SkipService = $True
                break
            }
        }

        If ($SkipService -eq $False){
            $FinalServices.Add($Service.key, $Service.value)
        }
        
    }

    return $FinalServices
}
# Get specific Windows OS object's parent VM.
# Commit new services to VM object

Get-vROpsAccessToken -RemoteCollector $RemoteCollector -Credential $Credential -AuthSource $AuthSource #-FunctionDebug $true
$WindowsOSObjectServiceStats = Get-WindowsOSObjServicesStats -RemoteCollector $RemoteCollector -Headers $Headers

#$WindowsOSObjectProperties = Get-WindowsOSObjProperties -RemoteCollector $RemoteCollector -Headers $Headers
#$ExactServices = Get-ExactServiceNameByTag -WindowsOSObjectProperties $WindowsOSObjectProperties
#$FinalServices = Find-BlackListedServices -ExactServices $ExactServices