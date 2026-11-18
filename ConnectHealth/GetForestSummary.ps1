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

# SIG # Begin signature block
# MIIo2AYJKoZIhvcNAQcCoIIoyTCCKMUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB57WPKivdIiTfB
# iKDqU4KueiBy4si71asjTArrbXEY5aCCDcMwggatMIIElaADAgECAhMzAAAA0wKI
# 2Gm93wIJAAAAAADTMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMzAxBgNVBAMTKkF6dXJlIFJTQSBQ
# dWJsaWMgU2VydmljZXMgQ29kZSBTaWduaW5nIFBDQTAeFw0yNjAzMDUxOTA2MTla
# Fw0yNzAzMDMxOTA2MTlaMIGCMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSwwKgYDVQQDEyNBenVyZSBQdWJsaWMgU2VydmljZXMgUlNBIENvZGUg
# U2lnbjCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAMmsOxnEYc0FiPlE
# +RHIYQgZmVwJCSoTtJ0ZrpzYU8Awa7Ukuoe6vyo1aNHmzB6QwyfRZLPb5ATRzzjz
# Ae+pVUulZX5SfdDTUOfLOOJ9p7iH6TOFBNQiFfaspBsYd2oF7stfIKCR8OtM0tew
# jXEBcDADjYCv4+lV3WS2otKwzqnCqsz8UV8SLOX2HmC2sQhk4On6Oj28RLEq8can
# 8h9xrt78iW4N4l98/gwT98W1TNQIsf8jB66CJRyxpOZ7BKfLih1gu2Zkr/OkG4+M
# ZMulSefgczJZctRI4WWC8WssoI9nFs3FfEGjkRSq7OsVumD02ZBWKklCwoNIo0eW
# 5PA2Jwi0WlmmI8xztjYsbXV00CKXfIkQEsUxD/lGpCm1xaaBIqgbxPHvH5EJhCPh
# KOXbIm37g7KRWf3+RDnCjq/pOYgcdmwp2aAiQwIoG4hFwHYVobAtj5QYw/XGaLAh
# p6SCNSBXBdfwq//ZJgj1deuPJQwTg0uPQlMEg7thfbTWBhg4vwIDAQABo4IBuTCC
# AbUwDgYDVR0PAQH/BAQDAgeAMB8GA1UdJQQYMBYGCCsGAQUFBwMDBgorBgEEAYI3
# WwEBMB0GA1UdDgQWBBToMh9qoEACbff9AUkZiJ9lR5AHcDBFBgNVHREEPjA8pDow
# ODEeMBwGA1UECxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMRYwFAYDVQQFEw00Njk5
# ODErNTA3MTgxMB8GA1UdIwQYMBaAFPEvupEWfN59Uicx9Xr71VhZaTo9MG8GA1Ud
# HwRoMGYwZKBioGCGXmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L0F6dXJlJTIwUlNBJTIwUHVibGljJTIwU2VydmljZXMlMjBDb2RlJTIwU2lnbmlu
# ZyUyMFBDQS5jcmwwfAYIKwYBBQUHAQEEcDBuMGwGCCsGAQUFBzAChmBodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL0F6dXJlJTIwUlNBJTIwUHVi
# bGljJTIwU2VydmljZXMlMjBDb2RlJTIwU2lnbmluZyUyMFBDQS5jcnQwDAYDVR0T
# AQH/BAIwADANBgkqhkiG9w0BAQwFAAOCAgEAokRajG6jg8NQ4+ul6plkF1wQGMih
# hBmNK8QgxN3R9x/z2tY39+vpxsCzd9m1HUtDaRFajaZiLGYBCmbqKMBi7dCD780g
# eh++I5UIOoeZpAYSLCKgGxvsS31XsH2uqySwmyVPIIlQli4hdoq/fuy48LtwWldp
# pZo0ufSO7PWw8p2SW9M7bd/BxqGBE72ep32BOL2Pp3D+cQlRFajfZ2X6vF3KWe5F
# 3pEemQkp2U9VdGuv9kvyxvJqSgJQ3jM1WK9QwuZSylhEkhXZOmRmidCeuZObpOlc
# ZWAKOPnp25PNVr8ZEAotUEc2byN7p6yOCizC/p4eZiSaAlGO9n54c2Wgudd+oHKD
# cLEnQZ36eNrlFNq9imUhz3N86Co2Dl7o1bwTRD8AjXXlZ+kz6dxZ6dap0+zVguKf
# JR1EPGINOaFhPI3WncWiMa3Iz6atBUi8LaXzNCv8s0JO/P92PaFaqwX/tIOcrjAT
# zXZgCnqk9+C2voF9UPQswm76zp/Y9d6guyQDgBzY+gnPk3sWZ5jtafmyFkF/iE6o
# Imyx3lkGlRu0ZiHeIKdBIk/0SiSjFXF7sPkeaSpNE2deogNDnNbpsvdIMJgUQbkR
# a2pX1i13QyOmXH+zn7DVOdhtcgps/OLgedvdevSbxicy5XKGbEbIdnYKMylByWCh
# yzZA2w7Kvt68sYMwggcOMIIE9qADAgECAhMzAAAAArLEk4h4WezTAAAAAAACMA0G
# CSqGSIb3DQEBDAUAMFsxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xLDAqBgNVBAMTI01pY3Jvc29mdCBSU0EgU2VydmljZXMgUm9v
# dCBDQSAyMDIxMB4XDTIxMDkwMjE3NDExOVoXDTM2MDkwMjE3NTExOVowYjELMAkG
# A1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEzMDEGA1UE
# AxMqQXp1cmUgUlNBIFB1YmxpYyBTZXJ2aWNlcyBDb2RlIFNpZ25pbmcgUENBMIIC
# IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEApd39LL3WcWCx5Uk4WB5GFXGt
# xqHKnVgZI3QWk4SARERVvc0P9CAjsjTJ3tcbo4TxWiavkUzG8rxO8ngtzos/0EPP
# YZJrUzQuXMcpfvnv/bgLRmd3NxwDWpCLTT4GaY6vimWbFHNMW/g+F3DzIE8X0YO8
# KWpXwBK+9uK1+NoPt1U84Utvs3t++3+paiAY3l6KzQVcKpUl2Y9llpfaHiIbSi2w
# CF+rzK9KUnRjA7iLkYN4tDBOww3VF/ZQAdAoJRiQWwtJDSaptpFsNmEH7akUv+r9
# zZrqGUcudqljJ/CU0VeQOHAAVYTN/AUcRHahHjZRrJ8322w7+na1aTfcKucd2d0k
# OshnqhDcP42CiX9NHwECBcIgzqx7piUsNOzFHCH1BQOrspWErLnwcYolSrCAhbQT
# ty+XNSXQd+395uEAtnIUOSGh/0LkKrhz/jzpcuNCrSdu4qwU2FBTTK8AFHd6iHDr
# cqmzrpSZrjygTQmao7GbOs++shNhyycHIqV6Ief7jKr5Oz8qu2qRDBBy6KQw+tnB
# cK2xiTExTJSfyCvyh7DbZYN4hAQIAzULP1Nx0lp2ytOgqpdBrZsCf8AAEBjKiA88
# 418a+iNMjcOVgPjZ60xr+A95klq9f7PvHx3/h5gGcn1YVKL2rS/68s4Zzd/IzYpC
# 2rl5VsdfmtXJZzpsnfkCAwEAAaOCAcIwggG+MBAGCSsGAQQBgjcVAQQDAgEAMB0G
# A1UdDgQWBBTxL7qRFnzefVInMfV6+9VYWWk6PTBUBgNVHSAETTBLMEkGBFUdIAAw
# QTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9E
# b2NzL1JlcG9zaXRvcnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsG
# A1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFA4MsWRpvS2x
# 1WsmpkfqVk6Aw+2KMGYGA1UdHwRfMF0wW6BZoFeGVWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFJTQSUyMFNlcnZpY2VzJTIw
# Um9vdCUyMENBJTIwMjAyMS5jcmwwcwYIKwYBBQUHAQEEZzBlMGMGCCsGAQUFBzAC
# hldodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29m
# dCUyMFJTQSUyMFNlcnZpY2VzJTIwUm9vdCUyMENBJTIwMjAyMS5jcnQwDQYJKoZI
# hvcNAQEMBQADggIBAGKfs8wGdeOcgnTH74ue50sNZadnx1mYnXgO5l9Syz92hROE
# sAzhyusdpNsmi6VRQQs13YCc6lf9ni16dQxPeyNgh09jIl8hhY9Gp8jo1vP4lUrt
# FG+faeXkQQwi5ETpQpL1kYFt/TZruxvTgT/sE382GGua1L+1UWN9GutWH3NeS7jm
# upa4LBRPODcSrEpDw4Zu2MFC2r9LJv9yWbkEeyiHdeEydv1Uu/cbV241/3QUvn+j
# zxdngvXyfHWV+TLaeWVjgcgDw8rwBquoBbiIpJMDcQaqfyz/jta1ApP6oQPZhtld
# U5gv4vu9AMKcVvCGADHq5y4zPsB7WuqJuDcCOwLtTkzegD++oAcMoMDeZ0zkPov9
# kR1CBobbQeFQ5JD4KJAPdPIdKJUJ9Uy5O/zciIoKeLctb/be0cLa1s3nuuWExyjK
# MiL4hV3uPuzjUwUFoPAmuZ9ef9gz6VH/lCq87vNYBtuv9dTnfW/eOv+MGKWauq3p
# T9vvLxNfID2djFX2JIwWZxvIiLbGB1wAeHGeldy9y/IVYRPpiImLJ5IlnDAm/yDB
# eIEX5mHQgcCuXopWxsB2wBO4/VMIQGk/KddmaS+IgRY+2e/fXlmNMLuc+g6lKc5V
# o7vBnO2s559m6cjl8HHDuYbWjKhGcANlrCIWxWj0n9wO7XkStEJ8NBGHBKIFMYIa
# azCCGmcCAQEweTBiMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMTMwMQYDVQQDEypBenVyZSBSU0EgUHVibGljIFNlcnZpY2VzIENv
# ZGUgU2lnbmluZyBQQ0ECEzMAAADTAojYab3fAgkAAAAAANMwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IIKU8utxBpmDI6T8yatxHE9UozS70e/g/kEPNXOBxsE5MEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggGAabq42ilcs7wMYGstYGsc9BfJIXjSOzQM
# f3r1wu4Hdx8g6ppaggmphurqoeij7P8IK5BjfUWWibpexTQlv2uzOLRM1x3ouqor
# dyo95fdOFLe1lL6PgGCGEHuOxN5+RXr9TIQArlWhQzCHPUpqAhkLGNU+J83fOTAj
# 8G33lSZsws5WhFn48wDxM52lStJSMgVX0cAPB50+TbA/Z8UtHxy4Lu46SWL34QXb
# BBVW7FtrPT8e/icyYYUQLaHBxgtC78QX53yNbtlNF42//xN4J0ttnx0N5DCfCiFM
# 7jiMQo/tEcTarldiGytRLXO3X3Z/eXCvFKIbjJl1fd3EfuRexqRFVVRlAlcqEpFL
# YWukDm4JEzSSiOprOsRh3LlZH1EWEhhhJMIIlqPd4PxsK4f2zAXkA4btzimvX8UU
# peCjEa07wI+ugLw25RKTdoiowQfkDogQxgyBWkRTd8TXC2NwSG4YH5R0bdDPkG6U
# et7aA/pYZRB7cOADzngCGzbgMx44zzQ3oYIXsDCCF6wGCisGAQQBgjcDAwExghec
# MIIXmAYJKoZIhvcNAQcCoIIXiTCCF4UCAQMxDzANBglghkgBZQMEAgEFADCCAVoG
# CyqGSIb3DQEJEAEEoIIBSQSCAUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEICubyJuQDbKysB8WH5I8Z80kHmWOQSMER5vrcu0AISsIAgZq82yO
# aokYEzIwMjYxMTE3MDExMDUwLjM2NVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjU5MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIR/jCCBygwggUQoAMCAQICEzMAAAI494TFhCu+5OQAAQAAAjgw
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjYxMDE1MTgzNzQ3WhcNMjgwMTExMTgzNzQ3WjCB0zELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQg
# T3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046NTkx
# QS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDYw6K9AQa01hseA/LT
# RbENc2ZOIK5Vzgaa5f3d8Kn766e41lsmJqmTjr+bt7DT325Wr6AbLGM42JTKG3PZ
# FPudR5kl8f5dF16y1RX4BFRkrB/NrzVi1qgKCC/ZvobviPbGO/5WXOOCHGbna6vq
# 2Hf87fH9A/TV9Tjww1iHOZZK3z0+ijxF9rNLbYFtxxGDOcwj/+NKVyP07cSeYmLC
# 83ZZil0lDXWcpmUm/w/6QE90OnzQhPl7DURJZ0hWiX8h05DRGIwSQsb10RTYvICP
# 8NQMvDcMeuN6/5N2EkndSWhPSiu//QOJzaic4uoq1XnocL+3OsRg0xslTo8J9DiO
# Z3pL7B+n5A/TGT3l6+7s4nffV5iYoJ4A2Yj++QVLVHvawRxCvmRQouBj7tmAtVOb
# zyEdvtbdstWf7aY+1rj1lhChqnaYkdNYDwRoxVSHyFf9ZMC8PIIPoiao9a0RAVLj
# RnJMitmQKLCeFj7c+DUeYR+sUewG4e8BVCUp6XrH808Ac+fKwO2UuUlZ8VtU9nvq
# kID1fQMoxBmr1r/Am10ruKPtNVef7cUM+3eHU88ltrNGSuQ18j9nEb7RmxFceFn4
# uOAxoh82u7qHvRCKzmn2yGheeLAMGoToUszjg5TJgJoh27uVHrWzRA8PjPGi51W0
# xIr1OvOL9K3mWMHAimhQq/XBMQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFE2Veozc
# hTpFMGV6D/x2Rl9XQuy6MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1Gely
# MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNy
# bDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
# QSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQBg4+DBBLd+
# xa5MCNa1UR8A2LHLlLEJsLS0IES5McevXtFWkKvFS0ur6Z51Wt6VwsJ7aeWcK2xv
# zACa3xLQDs2NMFSnxMAyCpNN5b4gtqbNFmEC0K2T2a+XM8afb1+Vco2JXsCDf0Dk
# sf3v/YxsobYqmsXoXUFS1A7QvDpWDRNT21mHfB6oPMGnkz5ZjS1X1yP2FM70D1Gc
# k1aMuRVbn5rWKASu1Ro8SPuPqO1PswmJ5wE7sx7W4x/x1TWXN3JfrRLaexWUeBKL
# +DotBtm8hRg3BxY9YMgGWg/FdLm5d2sd6fid3fcZiyzMsFSj9Y3L6vF1bAaQ/IwV
# 5kMwScx8WlbpTZL6ta9jZxMaQ6LTHsrpvbh4c1cFckNqEt/BXiD7XXLa4pUmqGWk
# musIlvoW0JvxMy7NoOHktU+SNXCFElZ0Jsng26pFrCBVDS56MgV2pC2QVdGrdmh4
# +g3KbW8CbQ/X+vauamJeVO6TwH+xTFp//1UJrRVXeUF6hhmH7WPo4OBtmnKYzwVx
# m2QO3g0PNdNBNuFx4FlHQ6DS/nQggAuKcyQV856GmwcDpgAdBNoBmNrdVezQZa4J
# +C5WjdLuBeIUkaKPfhVJ+t4Rkc2hyk6uPqYqYO2j5afibYpAU8mfl9kB7dvaLb9Y
# 2ciug4LFEwjbg2QmlFz717+9KTZqLVKmITCCB3EwggVZoAMCAQICEzMAAAAVxedr
# ngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRp
# ZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4
# MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qls
# TnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLA
# EBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrE
# qv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyF
# Vk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1o
# O5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg
# 3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2
# TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07B
# MzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJ
# NmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6
# r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+
# auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3
# FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl
# 0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUH
# AgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0
# b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMA
# dQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAW
# gBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8v
# Y3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRf
# MjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEw
# LTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL
# /Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu
# 6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5t
# ggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfg
# QJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8s
# CXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCr
# dTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZ
# c9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2
# tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8C
# wYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9
# JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDB
# cQZqELQdVTNYs6FwZvKhggNZMIICQQIBATCCAQGhgdmkgdYwgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjU5MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBc+ChhD6tBwdsbRzmBXx7xDDPb5aCB
# gzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEB
# CwUAAgUA7qXTSDAiGA8yMDI2MTExNjE5MDg1NloYDzIwMjYxMTE3MTkwODU2WjB3
# MD0GCisGAQQBhFkKBAExLzAtMAoCBQDupdNIAgEAMAoCAQACAgMhAgH/MAcCAQAC
# AhKBMAoCBQDupyTIAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKg
# CjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAKGLT2Wd
# E0QZWC7zUBLrivbO63RcwIfgNaTMwC+Bb4CCXAcb5r6ya5H313a3pNMcO3wVtW2X
# FZleaxqIU6/7qrZdGIvbM8Ze4Tjz7u2axMVrJ4cxGzIbk0jc1dFztLSRAR4c2C7g
# DZZ2hzGOwoEoYjQEGZ3atu/b+PGmis/awUkhdWGc75k7p6fi/2s0JO9dY2I1yrwl
# /EfTGgOY+9EPLuy/TvVliaFgIVMvx7Szkwv3XF9zTLBD/SiGNeMTLNZgjaRTI1o7
# Je+bJMOiFDNqI4n8jpQtgGmxrr3l42Z5tXGTHJ+IyeJxHLIAuHrhdMkRIxgKrrz/
# Y7DU4irirQSqeXMxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAjj3hMWEK77k5AABAAACODANBglghkgBZQMEAgEFAKCCAUow
# GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCzMK4I
# UTNw16QnEsMNxl4wNzxRTX4Vw1oH4kIn8X5AAjCB+gYLKoZIhvcNAQkQAi8xgeow
# gecwgeQwgb0EIA56xCA0DqqhO7f128PwQ+63r8p/rY2B0q5Y8YtbCeK1MIGYMIGA
# pH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAI494TFhCu+5OQA
# AQAAAjgwIgQgbd+hwZYySdjZNrLkbFBI9eXG1AntESy6gNllc82KHn8wDQYJKoZI
# hvcNAQELBQAEggIALRkYLYGMn9u40Jvuxsp/LK1qcP+pprrJsAGa4Zc1JaPyT78s
# i7cM6WRxzfGwMMAQ6yXXjZ0kxki+sr46Vs6lnx06+s5x3GrTWKWVSVsL1EFmjayy
# lCY3m+mXMTIESr2G/h6WWoc1TH60LbS0PXYm0NRcnJMPEGewFxF0Dk9KOE66cJ06
# ZQLhJ7HGd2tWvoq4gviP1gR6uVw8zMczjsA0U8BIV6BMlEnSshAJ7WfUpg+bg2sT
# gLcrSpI4KRHoSGJitaFkaOBX4Ngx9jokbQTAjKTdtUmzon5u2O6663ca5RzeOdCv
# N6uDuHQot6cURy2PODCTHbE1FlnG4wxP+1LFT0+jkAe24PeSSRLgd4hkjiPp05IJ
# aOXmXDolSl/HrJE4WU/qzxQLGZYg+rD6TbVXkDXy+KaTi8dyhq/5nahih2jRWcb5
# UTE5TCaWIDIrtbhJgzMr77iFBcFwjhpSlapBBflczBqwkr07rj2NQlE4H/cphDRH
# 3maqU7OoTIGmcVq4fq8Bzb8h2arRSkp++NuTdMYUWTSJOf6M8+NTm1K6x9jgs6lz
# XYMhzWk+wY7c4SSo/Yxi1G4cLYGUGLQuFklch08IM3aNxrowqPGMGoVsH1rm/N3A
# VZUnTHC8S9XgF1triK6lsPZF+q36RHBA9ok71WBacbbChTt8535Cz9daomk=
# SIG # End signature block
