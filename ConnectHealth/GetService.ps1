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

# 3. Get the complete service list for the signed-in tenant.
$servicesUri = 'https://management.azure.com/providers/Microsoft.ADHybridHealthService/services'
$requestParameters = @{
    Uri = $servicesUri + '?api-version=2014-01-01'
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

    Write-Host "`nGetServices: GET $($requestParameters.Uri)"
    $servicesResponse = Invoke-RestMethod @requestParameters
    if ($null -eq $servicesResponse -or $null -eq $servicesResponse.PSObject.Properties['value'])
    {
        throw 'The services response did not contain the expected value collection.'
    }

    $servicesResponse | ConvertTo-Json -Depth 50

    # 4. Get and print the details of each service.
    #    Failed calls report HTTP status and message, then move to the next service.
    foreach ($service in $servicesResponse.value)
    {
        if ([string]::IsNullOrWhiteSpace($service.serviceName))
        {
            throw 'A service in the list did not contain a serviceName.'
        }

        $serviceName = [Uri]::EscapeDataString($service.serviceName)
        $requestParameters.Uri = '{0}/{1}?api-version=2014-01-01' -f $servicesUri, $serviceName
        Write-Host "`nGetService: GET $($requestParameters.Uri)"
        try
        {
            $serviceDetails = Invoke-RestMethod @requestParameters
            if ($null -eq $serviceDetails)
            {
                throw "GetService returned no response for '$($service.serviceName)'."
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

            Write-Warning "GetService failed for '$($service.serviceName)'. HTTP status: $httpStatus. Message: $message Skipping this service."
            continue
        }

        $serviceDetails | ConvertTo-Json -Depth 50
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
# MIIo5AYJKoZIhvcNAQcCoIIo1TCCKNECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBy9NoonEyCs9md
# /5ubO937fTVRL4iLCMr/6BQUOlxyZ6CCDdIwgga8MIIEpKADAgECAhMzAAAA0ths
# RrGdxrKgAAAAAADSMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMzAxBgNVBAMTKkF6dXJlIFJTQSBQ
# dWJsaWMgU2VydmljZXMgQ29kZSBTaWduaW5nIFBDQTAeFw0yNjAzMDUxOTA2MTha
# Fw0yNzAzMDMxOTA2MThaMIGCMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSwwKgYDVQQDEyNBenVyZSBQdWJsaWMgU2VydmljZXMgUlNBIENvZGUg
# U2lnbjCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBALNYpkb0/u3SEoGK
# Z4J4ym26Y4+rAdnOymK+3yjwP7qZLQvVbNCMS+sC1Ji/NAgwlcNYB/si1sbYzE88
# 5U+0c1BoDz6av0Z02Cxv1skzaErjLg/V6UaEYZfw2KZ9Blb1N5IBmxh7Q59GMx3A
# imG7KOHyRsBHLf+acOWJcJ0aPS7UW3WrDzv5tPoWVnw+/47KRRb9YAzbyvnqq7UL
# mqbpfHku9EHHOT6Lgr4y7XvI3cAuVp3nD2560YFrdYrV43x+0J3YrRJXQDOk9Vy5
# Zu5iGF2J8xa2u2DivumBbFAMG7qBKJxdG3ugEVjnqKUvE2rOz5SuFOoqrW1pLDWo
# LezQrPLEQL8HPb44WOd9t5lDEXZ0wnWvZXATmdbrm5yRd6nCCh+wqCzzTqNOS3gG
# vwp3Q8DCYL2oXhPF6t4KWzaAhCa8AnGQAJmcJtcYmntdnpezD6fKRDOmKi92U0vB
# Ob/POQNBLCzvP7ubqNkQHd3uGI6qy7PjswR+ZQmqW46KgMPp3wIDAQABo4IByDCC
# AcQwDgYDVR0PAQH/BAQDAgeAMB8GA1UdJQQYMBYGCCsGAQUFBwMDBgorBgEEAYI3
# WwEBMB0GA1UdDgQWBBRipXg1H4MnCFC0cApmoyjgewxpGTBUBgNVHREETTBLpEkw
# RzEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVk
# MRYwFAYDVQQFEw00Njk5ODErNTA3MTg3MB8GA1UdIwQYMBaAFPEvupEWfN59Uicx
# 9Xr71VhZaTo9MG8GA1UdHwRoMGYwZKBioGCGXmh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY3JsL0F6dXJlJTIwUlNBJTIwUHVibGljJTIwU2VydmljZXMl
# MjBDb2RlJTIwU2lnbmluZyUyMFBDQS5jcmwwfAYIKwYBBQUHAQEEcDBuMGwGCCsG
# AQUFBzAChmBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL0F6
# dXJlJTIwUlNBJTIwUHVibGljJTIwU2VydmljZXMlMjBDb2RlJTIwU2lnbmluZyUy
# MFBDQS5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQwFAAOCAgEAowxRfRhV
# RQJOoTnTGGX0+TSFF+QsPXh4h29z79zDCAqzaZEMwbrr90ZujKGWPWmiBWye+HQH
# KomgVBg/9urNAiBclkzvvzFFDdvlETNT7qwQV2cMF1Z7aVPdKgRkPiA8ZyqPoFnD
# /V0kMt56e/2FQipkwYTbwhnHboIhVeiJ5Sr0GPr1nSejRvO7PHbRDA6pnrKGJRP1
# S07NIXnlPcMmXHcI4Rh9BA86ia+PZXqUhWm6be/s4VKMbNMloJxj8kpioMetwMJ2
# Zq7fMCIIyQ0mTk2ayDkE+N6zswwv9wL7p9Kz4vc3VzyKUa1juCG6U2cGcm/5Rm4P
# uKDmAA0uTjAr8jljYG3EC02jCzKe2Fv1OdyTmdgnqLcfJZRzbhO5dcAX750b4fxh
# 6zXq8kseoflvbHLBUl6UsWlg6PuS8ZPyMkVkpQAl7Vz/8PWsGQBj4FPf2aQAR3zU
# Hn2lMc7BVL25XFzAZrfIRevKFZuHjiotAT2R+HxvKmra8t5JhlBfmSfcvHLOT5bj
# UyZptkdK7ZFfu97bTUGSSka6rw8vsh1BPy5trpaq/s97CLPgexR9zSX4+FxeB+fU
# CsmJRbVLDD3awsWTsLRQK58yO3G/EzCR8lx51lZV6V7bU7M4RdLMV/k6Q+Dqd7sk
# 69l4liYJoUhMkT72FrpNKz5NzM/rUVHv6m0wggcOMIIE9qADAgECAhMzAAAAArLE
# k4h4WezTAAAAAAACMA0GCSqGSIb3DQEBDAUAMFsxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLDAqBgNVBAMTI01pY3Jvc29mdCBS
# U0EgU2VydmljZXMgUm9vdCBDQSAyMDIxMB4XDTIxMDkwMjE3NDExOVoXDTM2MDkw
# MjE3NTExOVowYjELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEzMDEGA1UEAxMqQXp1cmUgUlNBIFB1YmxpYyBTZXJ2aWNlcyBDb2Rl
# IFNpZ25pbmcgUENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEApd39
# LL3WcWCx5Uk4WB5GFXGtxqHKnVgZI3QWk4SARERVvc0P9CAjsjTJ3tcbo4TxWiav
# kUzG8rxO8ngtzos/0EPPYZJrUzQuXMcpfvnv/bgLRmd3NxwDWpCLTT4GaY6vimWb
# FHNMW/g+F3DzIE8X0YO8KWpXwBK+9uK1+NoPt1U84Utvs3t++3+paiAY3l6KzQVc
# KpUl2Y9llpfaHiIbSi2wCF+rzK9KUnRjA7iLkYN4tDBOww3VF/ZQAdAoJRiQWwtJ
# DSaptpFsNmEH7akUv+r9zZrqGUcudqljJ/CU0VeQOHAAVYTN/AUcRHahHjZRrJ83
# 22w7+na1aTfcKucd2d0kOshnqhDcP42CiX9NHwECBcIgzqx7piUsNOzFHCH1BQOr
# spWErLnwcYolSrCAhbQTty+XNSXQd+395uEAtnIUOSGh/0LkKrhz/jzpcuNCrSdu
# 4qwU2FBTTK8AFHd6iHDrcqmzrpSZrjygTQmao7GbOs++shNhyycHIqV6Ief7jKr5
# Oz8qu2qRDBBy6KQw+tnBcK2xiTExTJSfyCvyh7DbZYN4hAQIAzULP1Nx0lp2ytOg
# qpdBrZsCf8AAEBjKiA88418a+iNMjcOVgPjZ60xr+A95klq9f7PvHx3/h5gGcn1Y
# VKL2rS/68s4Zzd/IzYpC2rl5VsdfmtXJZzpsnfkCAwEAAaOCAcIwggG+MBAGCSsG
# AQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTxL7qRFnzefVInMfV6+9VYWWk6PTBUBgNV
# HSAETTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBkGCSsGAQQBgjcUAgQM
# HgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1Ud
# IwQYMBaAFA4MsWRpvS2x1WsmpkfqVk6Aw+2KMGYGA1UdHwRfMF0wW6BZoFeGVWh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFJT
# QSUyMFNlcnZpY2VzJTIwUm9vdCUyMENBJTIwMjAyMS5jcmwwcwYIKwYBBQUHAQEE
# ZzBlMGMGCCsGAQUFBzAChldodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L2NlcnRzL01pY3Jvc29mdCUyMFJTQSUyMFNlcnZpY2VzJTIwUm9vdCUyMENBJTIw
# MjAyMS5jcnQwDQYJKoZIhvcNAQEMBQADggIBAGKfs8wGdeOcgnTH74ue50sNZadn
# x1mYnXgO5l9Syz92hROEsAzhyusdpNsmi6VRQQs13YCc6lf9ni16dQxPeyNgh09j
# Il8hhY9Gp8jo1vP4lUrtFG+faeXkQQwi5ETpQpL1kYFt/TZruxvTgT/sE382GGua
# 1L+1UWN9GutWH3NeS7jmupa4LBRPODcSrEpDw4Zu2MFC2r9LJv9yWbkEeyiHdeEy
# dv1Uu/cbV241/3QUvn+jzxdngvXyfHWV+TLaeWVjgcgDw8rwBquoBbiIpJMDcQaq
# fyz/jta1ApP6oQPZhtldU5gv4vu9AMKcVvCGADHq5y4zPsB7WuqJuDcCOwLtTkze
# gD++oAcMoMDeZ0zkPov9kR1CBobbQeFQ5JD4KJAPdPIdKJUJ9Uy5O/zciIoKeLct
# b/be0cLa1s3nuuWExyjKMiL4hV3uPuzjUwUFoPAmuZ9ef9gz6VH/lCq87vNYBtuv
# 9dTnfW/eOv+MGKWauq3pT9vvLxNfID2djFX2JIwWZxvIiLbGB1wAeHGeldy9y/IV
# YRPpiImLJ5IlnDAm/yDBeIEX5mHQgcCuXopWxsB2wBO4/VMIQGk/KddmaS+IgRY+
# 2e/fXlmNMLuc+g6lKc5Vo7vBnO2s559m6cjl8HHDuYbWjKhGcANlrCIWxWj0n9wO
# 7XkStEJ8NBGHBKIFMYIaaDCCGmQCAQEweTBiMQswCQYDVQQGEwJVUzEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTMwMQYDVQQDEypBenVyZSBSU0EgUHVi
# bGljIFNlcnZpY2VzIENvZGUgU2lnbmluZyBQQ0ECEzMAAADS2GxGsZ3GsqAAAAAA
# ANIwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# LwYJKoZIhvcNAQkEMSIEIJXG0cz/BMTJ5S1kqaOUVOlDAercMVSnPOCN8oOLIw7d
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggGAWyqSPSKB7DXG
# SlFK4miRs1d3+Ue8fKyBj5D7poN1vb47pxpAZHF17HvwxWbsrHQiaScL5I9j41Ag
# 4IIp7t+NvYF0U3/LRrkL/Jx6lr+rzaDwv+4wgFRzxuS89va8yWQPQDrxOHTG+2Kt
# sBVZslktKZowELkmfKcaMa56gghfeC2467dMMvudKOY4rZa9Bap0lUd079XqeWMj
# ucA5p806wqhN1CM0Y3juPJTqkvvnPNSnnH8V6GsrRORatjjT3FvvhK+yROWPxFdU
# eZJ0K6gGuvLwxNtGXCWKiQHlweHtmzW+vcPjxptM30iaiSY2iUw18QtaId897sd1
# GKDqbWlGSBe2rbpX0ik3U7Ns9FNtRJTzmGaRpIN8ER6qaLQkT05ARcW78yhEobtR
# /aib9NaX4Ee8HooDptqxZwlJ2xld5NbpmlOcDwCg3hjvQxAiSJDfuTEqMRAPnkdr
# xHcq1kUrChjFqxl2zzFicyL6o73CbMpnmm3o664Uj5qsbAv0XZywoYIXrTCCF6kG
# CisGAQQBgjcDAwExgheZMIIXlQYJKoZIhvcNAQcCoIIXhjCCF4ICAQMxDzANBglg
# hkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJEAEEoIIBSQSCAUUwggFBAgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEILDYTOtmi3NW8zCFX0udAQIRITUZaQVX
# GOWRoYF48CddAgZq82rBKLwYEzIwMjYxMTE3MDEwOTI3LjQ4NVowBIACAfSggdmk
# gdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
# BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR+zCCBygwggUQoAMCAQICEzMAAAIw
# PwcEM8T7OdYAAQAAAjAwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwHhcNMjYxMDE1MTgzNzM1WhcNMjgwMTExMTgzNzM1WjCB0zEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWlj
# cm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046NTUxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQDVwRBW2y1exyTQANEW30RXgtkbjibnGhGNMgd90qNcF6HbZMOlVjk2/FAF1C4i
# Bx/9p5fCdCin+Z6ZssW8KwvESArdjPZFd7/sNE7UhHt3zmgU2qpv+4SpU+09HmRq
# iltt/CbyZ4DwHp1E0TNJ69zkI7mQnxntgFaLAy2ypUgjOlZii2yaBuxhqwWBVJYe
# 7g0wUc6PknYpbx3a87tjAAavYlK9ncz0WKZ9P/isPK+X4nMMxD6539C6fqYx7idf
# g54/oIVA6600HlbQEHFA7GBwVpaZX9kPAPOTezYE+G7DvLwT0+TwS0q9QvbhIbwn
# a5KGsnX6wNokkjBcJJq5BXJ1P8jN1eTV3ZTWu11L+aMlHUSIoJ8BR9y6zBJl2WqF
# sk7YMbaFTpv34kPcLed0ok7NC4KUhc9cBxcwnWrcEse8dEDJPOT10jX6KyvJ+C1/
# 4CL+18kYjGlNhEVFRm/dS7G1GRtj9/V1MmO2SAFiqpkBZeHvOZ4AY4P6GimdYXef
# ZgFBoH76/BbXk+AizfU+qXJiOEjLNmxYZH39QebQZZPW4XBw6iFDVqZJ/opOJZso
# zYYklY+VXz05LgvacaVOaZzqQE5BHmXufqgHm0f+r9IDiPqG2vHqh9Vo5eXd6eAq
# arWHfQOSP2SvrpyG6pX445aMrdQ1mzKYi9EIhkosw1UIeQIDAQABo4IBSTCCAUUw
# HQYDVR0OBBYEFOKoYUNBGcCqpVEkCMzFm47bcbAFMB8GA1UdIwQYMBaAFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
# Q0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEB
# CwUAA4ICAQAB2HcW7x5FJppHuoLhl38Nf48DKFBQBXr+CJUJQaWSnG7SonxxC+t3
# 6ANDTGVmywG4+rCIe/03xhXUMXyziziOfagjVK/1PDqM6eqpC7HoZV930/S9IJTV
# HZ2fwWdCQOMNrhWJ8Y8LD4ruzjK60RYvkIPBYjjDlMlHvphVLfzoRmg76vgBt2jg
# QFwI0wbF6LsJSnnDMwQrVf6WvmH/I0x6KAufGwJPg2LJIJdn3FEIFGeJp4eUsvRX
# CN1TIrVNtlg6cHYZ+XLwgsv4Bht5hdUm6KU1XlOhBwnOtetTdrt474+eQy1x60Ae
# ySMOUkyBrplucHiS/CXhlUPH2BiT6ICtiFMZL2N3jkx3wN1eE0D8Sna9Pwd7GuJ4
# PPZ+HokzeH9QVoE+9xUf6wJY8+korNf1MaU989qZg75yPKS4d8P96vJXwxka0n/m
# j6V90xl/iYfNEXirlT4lHo2I1q4aLr6kChGAxWe5J0LVfzBkRcep6rHqHzYY2f+b
# snQ7flSdeQF81dq3bagKv1FGbMu744qxxspr8l9z4R4sodeB+Piz4wNUQ/htBQU4
# M3bZIBVU/tgKabAOhfz67vB69oYQV4NuH6fk7oUhGgY7FJxP3oLRK+G10wzLMP10
# Ocm24NljJdZT6LSoVBHdYfCx3U3zgRLHlBTw6y10tBq7RKmkYxjzwDCCB3EwggVZ
# oAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jv
# c29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4
# MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvX
# JHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa
# /rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AK
# OG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rbo
# YiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIck
# w+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbni
# jYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F
# 37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZ
# fD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIz
# GHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR
# /bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1
# Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUC
# AwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0O
# BBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yD
# fQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkr
# BgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUw
# AwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBN
# MEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0
# cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoG
# CCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9
# /Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5
# bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvf
# am++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn
# 0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlS
# dYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0
# j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5
# JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakUR
# R6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4
# O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVn
# K+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoI
# Yn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNWMIICPgIBATCCAQGhgdmk
# gdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
# BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCnszgvh8f2
# WUeirqwnKpMhjr7BPqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7qXRejAiGA8yMDI2MTExNjE5MDExNFoYDzIw
# MjYxMTE3MTkwMTE0WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDupdF6AgEAMAcC
# AQACAgfqMAcCAQACAhPJMAoCBQDupyL6AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEL
# BQADggEBADVP6/7SuVfJ2CFxTcTi0k7eUGtB+DG8q2s8OvegDt84ApumChJudhOY
# 5nfWHF10+HDjWPHXW2vlswLBqMhnhZYzXV2UVEodLe1EYFJTqqozux1VuDVKMmgN
# iYw8uBC1QnmGfwTcMIyvjWxH+V8VQFA/YS1jXnXks5l3Lz5p8ziaqJ8MDhtyacHn
# zqOAWEv2PrqwcIdYgttGgf8uafbGyKmaBmNiqGxKpq1sokr71mBG01jmiy6MM52s
# mbg7sgWagZBgrn3AoGx87nHnrbc8DE51Tz8R782mWHz8CchAe8CyQD35lL0ZBFRG
# VIASo4I8i3AK4rqus8GxI9mimZLO/sIxggQNMIIECQIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAjA/BwQzxPs51gABAAACMDANBglghkgB
# ZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCAEXKlhsfKt+b1gKnaYzBbt1uRCtVKYvfhMHxncpRzg6TCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EIBSSWLrvRZbPgVa4c8ZpeOnOU3JHYBu9Ox7c
# qaICH9FoMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIwPwcEM8T7OdYAAQAAAjAwIgQgpDafyCHNlL3SO+Zt4m8Gi59s/jDiMQZ602El
# a1iJSkAwDQYJKoZIhvcNAQELBQAEggIAhOo1CxU3xylu18W8YkDfg/NSnYfKDTvL
# 7Sun0vo5MlVNu6Z68BdITEjjxfvO7IG/C/9D6lm47HyTADt47HCDMnRhfN93oq2g
# QV9VjmgskiwtwOpC4mWHXfxZEDuN3Ez++xT2FFNYD/BqpeVi3AYQOmeKAuNG13Ys
# v1ElDe9FAru8YUD08UkpcO3d5YWxWs3xsNYG01PEepTH4PL4+uHG4uJnTzEeFYP4
# R5opV6F6aA+EtX05RpPZffsD/eSqnkfrRaWWAggEJDyukfaT6J7s42d5H52Fj7VF
# gS11kmhSXprDixQ4ZykNHEkXb8K3eCbFOiJnCmjwky9LVZFy1HzY0R+3A+Ojlgzb
# UEoNfJcNA2ojeMhUIkw7YojAhzBNvC/UjJFIooWSUP9E2PY/yWA7V7MlZHQ5IJOf
# rA6CJKenJpMyuzV+aG2Gomcl/QuYaOniqLxSXiivXMgdIAEcKtHcp9UTErY3lx/D
# MjWf3q/9KNaYXgwXy4ekxXeLtI8sgFhwEoF2DbpAjnfpJvth5dEdCyYvhR+Ml/ns
# UyOQ3Psv0ir/A5hr7xRLB4Upb8PXZLYqEKG/rGrHBOBMibsSD11QkkviPPk+Gta8
# Yl4Lzs3Z/uVfwLMarIu7bggOsJmQOrGKngjjUe76BB6Tr84LBCizTjtrH5MqzBqH
# bOLzDKVTP2k=
# SIG # End signature block
