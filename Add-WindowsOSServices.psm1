function Add-WindowsOSServices {

    param (
        [Parameter(Mandatory=$true)]$WindowsObjectUUID,
        [Parameter(Mandatory=$true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory=$false)]$AuthSource="",
        [Parameter(Mandatory=$false)]$RemoteCollector="10.0.0.27",
        [Parameter(Mandatory=$false)]$Commit=$false
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

    # Get the Windows OS Object's Automatic Services
    function Get-WindowsOSObjAutomaticServices {
        param (
            [Parameter(Mandatory=$true)]$RemoteCollector,
            [Parameter(Mandatory=$true)]$WindowsObjectUUID,
            [Parameter(Mandatory=$true)]$Headers,
            [Parameter(Mandatory=$false)]$FunctionDebug=$false
        )

        $WindowsOSObjectServicesStats = Invoke-RestMethod "https://$RemoteCollector/suite-api/api/resources/$WindowsObjectUUID/stats/latest?currentOnly=false&_no_links=true" -Method 'GET' -Headers $Headers -SkipCertificateCheck

        $StatList = $WindowsOSObjectServicesStats.values."stat-list"."stat"
        
        [System.Collections.ArrayList]$FinalOutput= @()

        #(?<=services:).*(?=\|)
        #/(?<=services:).*(?=\|)/g

        ForEach ($stat in $StatList) {
            If (($stat.statKey -match "startup.mode") -and ($stat.data -eq "2")) {
                $ServiceName = (Select-String -InputObject $stat.statKey -Pattern '(?<=services:).*(?=\|)').Matches[0]
                [void]$FinalOutput.Add($ServiceName) # void or else it will add a bunch of numbers when printing
            }
        }

        return $FinalOutput
    }

    # Get specific Windows OS object's service objects properties
    function Get-WindowsOSObjProperties {
        param (
            [Parameter(Mandatory=$true)]$RemoteCollector,
            [Parameter(Mandatory=$true)]$WindowsObjectUUID,
            [Parameter(Mandatory=$true)]$Headers,
            [Parameter(Mandatory=$false)]$FunctionDebug=$false
        )

        $WindowsOSObjectProperties = Invoke-RestMethod "https://$RemoteCollector/suite-api/api/resources/$WindowsObjectUUID/properties?_no_links=true" -Method 'GET' -Headers $Headers -SkipCertificateCheck

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
        #Write-Host $ExactServices
        $FinalOutput = @{}

        ForEach ($Service in $ExactServices.GetEnumerator()) {

            $SkipService = $False

            ForEach ($BLService in $BlackListedServices) {
                If ($Service.key -match $BLService) {
                    #Write-Host "SKIPPED: " $Service "|||||" $BLService
                    $SkipService = $True
                    break
                }
            }

            If ($SkipService -eq $False){
                $FinalOutput.Add($Service.key, $Service.value)
            }
            
        }

        return $FinalOutput
    }


    # Search for Service Display Name's "servicename" i.e. Windows Event Log would be "Eventlog"
    # Output will be a final hash table of the automatic services with their associated servicename from the Windows OS object metrics/properties
    # These will be later compared in the final Compare-ServicesFinal
    function Search-ForServiceName {
        param (
            [Parameter(Mandatory=$true)]$WindowsOSObjAutomaticServices,
            [Parameter(Mandatory=$true)]$CleanedServicesProperties
        )

        $FinalFromWinOSObj = @{}

        ForEach ($Service in $WindowsOSObjAutomaticServices) {
            #DEBUG Write-Host $Service.ToString()
            If ($CleanedServicesProperties[$Service.ToString()]) {
                #DEBUG Write-Host "MATCH: " $Service.ToString() $CleanedServicesProperties[$Service.ToString()]
                $FinalFromWinOSObj.Add($Service.ToString(), $CleanedServicesProperties[$Service.ToString()])
            }
        }
        return $FinalFromWinOSObj
    }

    # Get specific Windows OS object's parent VM. Returns UID of Parent Virtual Machine Object
    function Get-ParentVirtualMachine {
        
        param (
            [Parameter(Mandatory=$true)]$RemoteCollector,
            [Parameter(Mandatory=$true)]$WindowsObjectUUID,
            [Parameter(Mandatory=$true)]$Headers,
            [Parameter(Mandatory=$false)]$FunctionDebug=$false
        )

        $Relationships = Invoke-RestMethod "https://$RemoteCollector/suite-api/api/resources/$WindowsObjectUUID/relationships/PARENT?page=0&pageSize=-1&_no_links=true" -Method 'GET' -Headers $Headers -SkipCertificateCheck
        $ParentVirtualMachineUUID = ""
        ForEach ($resource in $Relationships.resourceList) {
            If ($resource.resourceKey.resourceKindKey -eq "VirtualMachine") {
                #DEBUG Write-Host $resource.resourceKey.name
                #DEBUG Write-Host $resource.identifier
                $ParentVirtualMachineUUID = ($resource.identifier).ToString()
            }
        }
        return $ParentVirtualMachineUUID
    }


    # Grab Windows OS object child services in preparation for final comparison. This will be fed into Compare-ServicesFinal
    function Get-WinObjChildServices {

        param (
            [Parameter(Mandatory=$true)]$RemoteCollector,
            [Parameter(Mandatory=$true)]$WindowsObjectUUID,
            [Parameter(Mandatory=$true)]$Headers,
            [Parameter(Mandatory=$false)]$FunctionDebug=$false
        )

        $ChildServiceObjects = Invoke-RestMethod "https://$RemoteCollector/suite-api/api/resources/$WindowsObjectUUID/relationships/CHILD?page=0&pageSize=-1&_no_links=true" -Method 'GET' -Headers $Headers -SkipCertificateCheck

        $ServicesMonitored = @{}

        ForEach ($resource in $ChildServiceObjects.resourceList) {
            $ServiceDisplayName = ""
            $ServiceTrueName = ""
            If ($resource.resourceKey.resourceKindKey -eq "serviceavailability") {
                # Service Display Name + Windows OS on SERVERNAME
                #DEBUG Write-Host $resource.resourceKey.name
                $ServiceDisplayName = $resource.resourceKey.name

                ForEach ($identifier in $resource.resourceKey.resourceIdentifiers) {
                    If ($identifier.identifierType.name -eq "FILTER_VALUE") {
                        # The actual service NAME (not display name)
                        #DEBUG Write-Host $identifier.value
                        $ServiceTrueName = $identifier.value
                        break
                    }
                }
            }

            # Add to hash table, key is Display Name, value is Service Name.
            $IndexOfLastOn = $ServiceDisplayName.LastIndexOf(" on")
            $ServiceDisplayName = $ServiceDisplayName.Substring(0,$IndexOfLastOn)
            $ServicesMonitored.Add($ServiceDisplayName,$ServiceTrueName)
        }

        return $ServicesMonitored
    }


    # Check for services that are already added? I.E. Don't try to add a additional serviceavailibility that is already monitoring Windows Event Log / "Eventlog"
    # Outputs final list of services to commit to the Virtual Machine object.
    function Compare-ServicesFinal {
        param (
            [Parameter(Mandatory=$true)]$ServicesMonitored,
            [Parameter(Mandatory=$true)]$FinalFromWinOSObj
        )

        $ServicesToAdd = @{}

        ForEach ($AutomaticService in $FinalFromWinOSObj.GetEnumerator()) {

            $SkipService = $False

            ForEach ($MonitoredService in $ServicesMonitored.GetEnumerator()) {
                If ($AutomaticService.key -eq $MonitoredService.key) {
                    $SkipService = $True
                    #DEBUG Write-Host "SKIPPED: " $AutomaticService.key $AutomaticService.value "BECAUSE: " $MonitoredService.key $MonitoredService.value
                    break
                }
            }

            If ($SkipService -eq $False) {
                #DEBUG Write-Host "Adding: " $AutomaticService.key "|" $AutomaticService.value
                $ServicesToAdd.Add($AutomaticService.key, $AutomaticService.value)
            }
        }

        return $ServicesToAdd
    }


    # Finally, commit new automatic services to VM object that already don't exist
    function Invoke-NewServices {
        param (
            [Parameter(Mandatory=$true)]$RemoteCollector,
            [Parameter(Mandatory=$true)]$AutomaticServices,
            [Parameter(Mandatory=$true)]$CurrentVM,
            [Parameter(Mandatory=$true)]$Headers,
            [Parameter(Mandatory=$false)]$FunctionDebug=$false
        )

        # If no services to add just exit.
        If ($AutomaticServices.count -eq 0){
            Write-Host "No services to add. Exiting."
            return $null
        }

        #$FirstAutoService = $AutomaticServices[0]
        #$jsonBody = "{ `"services`": [ { `"serviceName`": `"serviceavailability`", `"configurations`": [ {`"configName`": `"$($FirstAutoService.DisplayName)`",`"isActivated`": true,`"parameters`":[{`"key`":`"FILTER_VALUE`",`"value`":`"$($FirstAutoService.Name)`"}]}]}]}"

        ForEach ($service in $AutomaticServices.GetEnumerator()){

            $jsonBody = "{ `"services`": [ { `"serviceName`": `"serviceavailability`", `"configurations`": [ {`"configName`": `"$($service.key)`",`"isActivated`": true,`"parameters`":[{`"key`":`"FILTER_VALUE`",`"value`":`"$($service.value)`"}]}]}]}"

            If ($FunctionDebug -eq $true){
                Write-Host "function Invoke-NewServices DEBUG: `$jsonBody contents: "$jsonBody
            }

            try {
                Invoke-RestMethod "https://$RemoteCollector/suite-api/api/applications/agents/$CurrentVM/services?_no_links=true" -Method 'POST' -Headers $Headers -Body $jsonBody -SkipCertificateCheck
            }
            catch {
                Write-Host "function Invoke-NewServices ERROR: Service: $($service.key) with exec name $($service.value) either exists already or Invoke-RestMethod failed due to JSON formatting."
            }
        }
    }

    Get-vROpsAccessToken -RemoteCollector $RemoteCollector -Credential $Credential -AuthSource $AuthSource #-FunctionDebug $true
    $WindowsOSObjAutomaticServices = Get-WindowsOSObjAutomaticServices -RemoteCollector $RemoteCollector -WindowsObjectUUID $WindowsObjectUUID -Headers $Headers
    $WindowsOSObjectProperties = Get-WindowsOSObjProperties -RemoteCollector $RemoteCollector -WindowsObjectUUID $WindowsObjectUUID -Headers $Headers
    $ExactServicesProperties = Get-ExactServiceNameByTag -WindowsOSObjectProperties $WindowsOSObjectProperties
    $CleanedServicesProperties = Find-BlackListedServices -ExactServices $ExactServicesProperties
    $FinalFromWinOSObj = Search-ForServiceName -WindowsOSObjAutomaticServices $WindowsOSObjAutomaticServices -CleanedServicesProperties $CleanedServicesProperties
    $ParentVirtualMachineUUID = Get-ParentVirtualMachine -RemoteCollector $RemoteCollector -WindowsObjectUUID $WindowsObjectUUID -Headers $Headers
    $ServicesMonitored = Get-WinObjChildServices -RemoteCollector $RemoteCollector -WindowsObjectUUID $WindowsObjectUUID -Headers $Headers
    $ServicesToAdd = Compare-ServicesFinal -ServicesMonitored $ServicesMonitored -FinalFromWinOSObj $FinalFromWinOSObj

    If ($Commit -eq $true) {
        Invoke-NewServices -RemoteCollector $RemoteCollector -AutomaticServices $ServicesToAdd -Headers $Headers -CurrentVM $ParentVirtualMachineUUID
    } elseif ($Commit -eq $false) {
        If ($ServicesToAdd.Count -gt 0) {
            Write-Host "`n`$Commit is set to TRUE, these are the services that would be committed to $WindowsObjectUUID"
            ForEach ($Service in $ServicesToAdd.GetEnumerator()) {
                Write-Host $Service.key $Service.value
            }
        } else {
            Write-Host "No services to add for $WindowsObjectUUID`n"
        }
        
    }
}
