# Guide: run these sections in order in PowerShell, or run this file directly.
# Prerequisite: your user must have read access to Microsoft Entra Connect Health
# in the target tenant. Verify that you can open the Connect Health blades in
# the portal without receiving an "Access denied" error.
#
# Setup: copy and run this block separately before running the file.
# It installs a supported Az.Accounts version for your user if needed.
#
# if (-not (Get-Module -ListAvailable -Name Az.Accounts | Where-Object { $_.Version -ge [version]'2.17.0' }))
# {
#     Install-Module -Name Az.Accounts -MinimumVersion '2.17.0' -Repository PSGallery -Scope CurrentUser -ErrorAction Stop
# }
#
# The requirement below is checked before any commands in this file execute.
# Get-AzAccessToken -AsSecureString requires Az.Accounts 2.17.0 or later.
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.17.0' }

# 1. Reuse your current Azure sign-in, or sign in interactively if needed.
#    When prompted to select a subscription, press Enter to use the default.
#    To choose a different tenant or account, run this optional template first.
#    Replace <tenant-id-or-domain> with your tenant GUID or verified domain.
#    Replace <user-principal-name> with your sign-in name. Keep the quotes.
# Connect-AzAccount -Tenant '<tenant-id-or-domain>' -AccountId '<user-principal-name>' -ErrorAction Stop | Out-Null

#    Alternatively, use this device-code example instead of the command above:
# Connect-AzAccount -Tenant '<tenant-id-or-domain>' -AccountId '<user-principal-name>' -UseDeviceAuthentication -ErrorAction Stop | Out-Null

# 2. Request an ARM token using the context selected during sign-in.
$profile = Get-AzContext -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($profile.Account.Id) -or [string]::IsNullOrWhiteSpace($profile.Tenant.Id))
{
    Connect-AzAccount -ErrorAction Stop | Out-Null
    $profile = Get-AzContext -ErrorAction Stop
}

$signedInTenantId = $profile.Tenant.Id
if ([string]::IsNullOrWhiteSpace($profile.Account.Id) -or [string]::IsNullOrWhiteSpace($signedInTenantId))
{
    throw 'No Azure tenant context is available. Run Connect-AzAccount with your desired parameters first.'
}

$token = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/' `
    -TenantId $signedInTenantId -DefaultProfile $profile -AsSecureString -ErrorAction Stop

if ($token.Token -isnot [System.Security.SecureString] -or $token.Token.Length -eq 0)
{
    throw 'Token acquisition did not return a secure access token. Update Az.Accounts and try again.'
}

# 3. Get only AD DS services. Forest summaries do not apply to Sync or AD FS.
$addsServicesUri = 'https://management.azure.com/providers/Microsoft.ADHybridHealthService/addsservices'
$requestParameters = @{
    Uri = 'https://management.azure.com/providers/Microsoft.ADHybridHealthService/services?api-version=2014-01-01&serviceType=AdDomainService'
    Method = 'Get'
    Headers = @{ Accept = 'application/json' }
    MaximumRedirection = 0
    ErrorAction = 'Stop'
}

try
{
    if ($PSVersionTable.PSVersion.Major -ge 7)
    {
        $requestParameters.Authentication = 'Bearer'
        $requestParameters.Token = $token.Token
    }
    else
    {
        $credential = New-Object System.Management.Automation.PSCredential('Bearer', $token.Token)
        $requestParameters.Headers.Authorization = 'Bearer ' + $credential.GetNetworkCredential().Password
    }

    $servicesResponse = Invoke-RestMethod @requestParameters
    if ($null -eq $servicesResponse -or $null -eq $servicesResponse.PSObject.Properties['value'])
    {
        throw 'The services response did not contain the expected value collection.'
    }

    # 4. Get and print each forest summary.
    #    Failed calls report HTTP status and message, then move to the next forest.
    foreach ($service in $servicesResponse.value)
    {
        if ([string]::IsNullOrWhiteSpace($service.serviceName))
        {
            throw 'A service in the list did not contain a serviceName.'
        }

        $serviceName = [Uri]::EscapeDataString($service.serviceName)
        $requestParameters.Uri = '{0}/{1}/forestsummary?api-version=2014-01-01' -f $addsServicesUri, $serviceName
        Write-Host "`nGetForestSummary: GET $($requestParameters.Uri)"
        try
        {
            $forestResponse = Invoke-RestMethod @requestParameters
            if ($null -eq $forestResponse)
            {
                throw "GetForestSummary returned no response for '$($service.serviceName)'."
            }
        }
        catch
        {
            $httpStatus = 'Unavailable (no HTTP response)'
            if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode)
            {
                $httpStatus = [int]$_.Exception.Response.StatusCode
            }

            $message = $_.Exception.Message
            if (-not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message))
            {
                $message = $_.ErrorDetails.Message
            }

            Write-Warning "GetForestSummary failed for '$($service.serviceName)'. HTTP status: $httpStatus. Message: $message Skipping this forest."
            continue
        }

        $forestResponse | ConvertTo-Json -Depth 50
    }
}
finally
{
    $requestParameters.Headers.Clear()
    $requestParameters.Clear()
    $credential = $null
    $token = $null
}
