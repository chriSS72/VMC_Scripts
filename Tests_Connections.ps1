<#

        ===========================================================================
        Created by: Christian Soto
        Organization: VMware
        Email: chsoto@vmware.com
        ===========================================================================

        IN THE CASE PS CAN'T RUN SCRIPTS, RUN THE LINE BELLOW:
        set-ExecutionPolicy RemoteSigned -Scope CurrentUser 
#>

Get-Date

function prepEnv {
    $global:RefreshToken = Read-Host "Enter your CSP API Token"
    $global:ORGID = Read-Host "Enter your ORG ID"
    $global:SDDCID = Read-Host "Enter your SDDC ID"

    $url = 'https://console.cloud.vmware.com/csp/gateway/am/api/auth/api-tokens/authorize'


    $results = Invoke-WebRequest -Uri $url -Method POST -Headers @{accept='application/json'} -Body "refresh_token=$global:RefreshToken"
    if($results.StatusCode -ne 200) {
        Write-Host -ForegroundColor Red "Failed to retrieve Access Token, please ensure your VMC Refresh Token is valid and try again"
        break
    }
    $accessToken = ($results | ConvertFrom-Json).access_token
    Write-Host "CSP Auth Token has been successfully retrieved and saved to `$globalv:cspAuthToken'"
    $global:cspAuthToken = $accessToken

    $headers = @{
        "csp-auth-token"="$accessToken"
        "Content-Type"="application/json"
        "Accept"="application/json"
    }
    $global:cspConnection = new-object PSObject -Property @{'headers' = $headers}

    $requestORG = Invoke-WebRequest -Uri https://vmc.vmware.com/vmc/api/orgs/$global:ORGID -Method GET -Headers $global:cspConnection.headers
    if($requestORG.StatusCode -ne 200) {
        Write-Host -ForegroundColor Red "Failed to retrieve Organization info, please ensure your Org ID is valid and try again"
        break
    }

    $requests = Invoke-WebRequest -Uri https://vmc.vmware.com/vmc/api/orgs/$global:ORGID/sddcs/$global:SDDCID -Method GET -Headers $global:cspConnection.headers
    if($requests.StatusCode -ne 200) {
        Write-Host -ForegroundColor Red "Failed to retrieve SDDC info, please ensure your SDDC ID is valid and try again"
        break
    }
    
    $TMP=($requests.Content|ConvertFrom-Json)
    return $TMP
}

function printEnv {
    $SDDCinfo = prepEnv

    Write-Host "`n---Environment's information---"
    $SDDCNAME = $SDDCinfo.name
    $SDDCVER = $SDDCinfo.resource_config.sddc_manifest.vmc_version
    $global:NSXRP = $SDDCinfo.resource_config.nsx_api_public_endpoint_url
    $global:NSXIP = $SDDCinfo.resource_config.nsx_mgr_management_ip
    $global:NSXFQDN = ($SDDCinfo.resource_config.nsx_mgr_url | %{ $_.Split('/')[2]; })
    $global:VCPRIVATEIP = $SDDCinfo.resource_config.vc_management_ip
    $global:VCPUBLICIP = $SDDCinfo.resource_config.vc_public_ip
    $global:VCFQDN = ($SDDCinfo.resource_config.vc_url| %{ $_.Split('/')[2]; })

    Write-Host "SDDC Name------------:" $SDDCNAME
    Write-Host "SDDC Version---------:" $SDDCVER
    Write-Host "SDDC ID--------------:" $global:SDDCID
	Write-Host "vCenter FQDN---------:" $global:VCFQDN
	Write-Host "vCenter Priv IP------:" $global:VCPRIVATEIP
	Write-Host "vCenter Pub IP-------:" $global:VCPUBLICIP
	Write-Host "NSX FQDN-------------:" $global:NSXFQDN
	Write-Host "NSX Reverse Proxy----:" $global:NSXRP
	Write-Host "NSX Priv IP----------:" $global:NSXIP
}

function runVCChecks {
    Write-Host "`n---Running Test-NetConnection to test 443 inbound access to vCenter---"
    Write-Host "Testing Private IP" $global:VCPRIVATEIP
    Write-Host "PASS:" (Test-NetConnection -ComputerName $global:VCPRIVATEIP -Port 443 -InformationLevel Quiet)
    #Test-NetConnection -ComputerName $global:VCPRIVATEIP -Port 443 -InformationLevel Quiet
    Write-Host "Testing Public IP" $global:VCPUBLICIP
    Write-Host "PASS:" (Test-NetConnection -ComputerName $global:VCPUBLICIP -Port 443 -InformationLevel Quiet)
    #Test-NetConnection -ComputerName $global:VCPUBLICIP -Port 443 -InformationLevel Quiet
    Write-Host "Testing FQDN" $global:VCFQDN
    Write-Host "PASS:" (Test-NetConnection -ComputerName $global:VCFQDN -Port 443 -InformationLevel Quiet)
    #Test-NetConnection -ComputerName $global:VCFQDN -Port 443 -InformationLevel Quiet
}

function runNSXChecks {
    Write-Host "`n---Running Test-NetConnection to test 443 inbound access to NSX Manager---"
    Write-Host "Testing Private IP" $global:NSXIP
    Write-Host "PASS:" (Test-NetConnection -ComputerName $global:NSXIP -Port 443 -InformationLevel Quiet)
    #Test-NetConnection -ComputerName $global:NSXIP -Port 443 -InformationLevel Quiet
    Write-Host "Testing FQDN" $global:NSXFQDN
    Write-Host "PASS:" (Test-NetConnection -ComputerName $global:NSXFQDN -Port 443 -InformationLevel Quiet)
    #Test-NetConnection -ComputerName $global:NSXFQDN -Port 443 -InformationLevel Quiet

    Write-Host "---Executing API Calls to test if NSX Manager responds as expected---"
    Write-Host "Testing NSX Reverse Proxy Call" $global:NSXRP
    Invoke-WebRequest -Uri $global:NSXRP/policy/api/v1/infra/sites/default/enforcement-points -Method GET -Headers $global:cspConnection.headers
    Write-Host "Testing NSX Private IP Call" $global:NSXIP
    Invoke-WebRequest -Uri https://$global:NSXIP/policy/api/v1/infra/sites/default/enforcement-points -Method GET -Headers $global:cspConnection.headers

    Write-Host "---Testing NSX-T Manager's API Reply using Reverse Proxy---"
    $global:NSXRP
    Write-Host "Tier-0 Test"
    Invoke-WebRequest -Uri $global:NSXRP/policy/api/v1/infra/tier-0s -Method GET -Headers $global:cspConnection.headers

    Write-Host "Tier-1 Test"
    Invoke-WebRequest -Uri $global:NSXRP/policy/api/v1/infra/tier-1s -Method GET -Headers $global:cspConnection.headers

    Write-Host "DNS Forwarders Test"
    Invoke-WebRequest -Uri $global:NSXRP/policy/api/v1/infra/dns-forwarder-zones -Method GET -Headers $global:cspConnection.headers
}

printEnv
runVCChecks
runNSXChecks
