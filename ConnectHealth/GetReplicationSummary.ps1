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

# 3. Get only AD DS services. Replication summaries do not apply to Sync or AD FS.
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

    # 4. Get and print replication summaries for each forest.
    #    Change withDetails=false to withDetails=true to include inbound neighbors.
    #    Failed calls report HTTP status and message, then move to the next forest.
    foreach ($service in $servicesResponse.value)
    {
        if ([string]::IsNullOrWhiteSpace($service.serviceName))
        {
            throw 'A service in the list did not contain a serviceName.'
        }

        $serviceName = [Uri]::EscapeDataString($service.serviceName)
        $requestParameters.Uri = '{0}/{1}/replicationdetails?api-version=2014-01-01&withDetails=false' -f $addsServicesUri, $serviceName
        Write-Host "`nGetReplicationSummary: GET $($requestParameters.Uri)"
        try
        {
            $replicationResponse = Invoke-RestMethod @requestParameters
            if ($null -eq $replicationResponse -or $null -eq $replicationResponse.PSObject.Properties['value'])
            {
                throw "The replication summary response for '$($service.serviceName)' did not contain the expected value collection."
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

            Write-Warning "GetReplicationSummary failed for '$($service.serviceName)'. HTTP status: $httpStatus. Message: $message Skipping this forest."
            continue
        }

        $replicationResponse | ConvertTo-Json -Depth 50
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
# MIIozgYJKoZIhvcNAQcCoIIovzCCKLsCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBozFgDaEyDnauB
# UVUZxgFqRLfI9tju8JMFUYTP222vkaCCDdIwgga8MIIEpKADAgECAhMzAAAA0ths
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
# 7XkStEJ8NBGHBKIFMYIaUjCCGk4CAQEweTBiMQswCQYDVQQGEwJVUzEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTMwMQYDVQQDEypBenVyZSBSU0EgUHVi
# bGljIFNlcnZpY2VzIENvZGUgU2lnbmluZyBQQ0ECEzMAAADS2GxGsZ3GsqAAAAAA
# ANIwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# LwYJKoZIhvcNAQkEMSIEIB3hVO+OnyLsSAttTkXBsaC/XX80VYVMnva7uXH94rcl
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggGAhVhVhyQnsJxc
# 05/f4OoID/ot36QbOvxyETHUJXqByxqkRX7G8HDsa3OVXyem2x/ix0uKa6rJsDBW
# Ta8T0p6qMTNTCZKM24BFECcGDeyaNOjLEMWVecIIdbxjfbOxVjPCyqO2UZZr+nzX
# gQYUNwp/uSVj5vi7lT4L5KfrvngIu8Vy/rUf9g6uvkR/dNeYMQwbuNEwurfh8nWl
# 8qu1peMCfGDeH1H5x8ZUDJ87CGeqJSLc/gvwOKJLnXL5inzlW4yS/LPuqzsQNGvQ
# TaMiGED4l3CYjApFz1KImJk09DgR3d0A2VpG3vyGE2xg5hBdJ3Bx26QuZp75BKpp
# U05KzhOgA+4DlqBnyqZe602a3q0860QKZiATHLW6JNQi5KudnqIe7hY7F59HJeu7
# OxFfS1rnjR4sFXJq7WghK/zu7e1waXyukq9D4iDPe6yzavs9Gj4uw2SVIbsguYPJ
# d8noh6barcSHi/G6A2cH9wxu4W7jRJ0/gut7VJkI9gJZP5PQ3M8qoYIXlzCCF5MG
# CisGAQQBgjcDAwExgheDMIIXfwYJKoZIhvcNAQcCoIIXcDCCF2wCAQMxDzANBglg
# hkgBZQMEAgEFADCCAVIGCyqGSIb3DQEJEAEEoIIBQQSCAT0wggE5AgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIGDw0K5iVxuSujt2UKxdWnZl7voMSFbe
# 6ec+ampWmsJaAgZq80y51VIYEzIwMjYxMTE3MDEwOTI5LjQyNVowBIACAfSggdGk
# gc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNV
# BAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjozMzAzLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEe0wggcgMIIFCKADAgECAhMzAAACITPANfvSDyGk
# AAEAAAIhMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI2MDIxOTE5Mzk1NFoXDTI3MDUxNzE5Mzk1NFowgcsxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBB
# bWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMzAz
# LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANtxMAKpTVi9GhzJYvY8
# v1/J//5QuzaortTVpmxGcNlKeUKvsruOADd4UIQkvkFnt1RMLQN5l6l/5kL7scRs
# Hgh3OYl9ABQMUV6upjlVMeZC8/ZcDeVZIWPvjSJ1wZQeCU/kf89sIlTsYAdY/Yd1
# wKN3HWVgCjQD7MsjvHCdNB4zI5dfbXYSDhSYM88mDF1MzDpYVVawE9ZEGLmAOLHL
# az7tHwAOTmVsEEUMHmHQKOs1Yg3u4IDMXmDu2usvydcgqnXSaP1HGFwZD62WG3pU
# i93KBFVNQZ3MUHb+cG8mpD2THEWW1BJPvR8R3HhPJoqjD9/n4FKHjPj/1/s1chVV
# Muf/yRwkB9GoWZGusW3cgpvLtWvOZi6hBYPSWY0W0ZDnsGsmQ+s8UA96TUAu1xtv
# sUfedCm+LyeDP8wVf/5yeY0VYVTb1VUubMH1e8tnFti+R5623SaHmV+1543asTBT
# Kt2sq5/P2HZLqltq174LaHTYKtfBKRrTHp7OlOYaQgksW3bm5v9Rhc0t0d2zEYPo
# R9yQ4igliybgxL0X+9Kos0crz0jS9MsGeBASnosgWQg1qdFPc+03Hek0pEolEAtz
# ovqaFbiEvhocvvj2o99Dva3moAybnGIpgyAnZZqeJ1Es24jbnUkg3utpp4D/a9vR
# cWRlwhtNHWl9AaxyjhTSDm2PAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQU5iMizmpr
# ql+6q4/LIrUVOvlAMKcwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEF
# BQcDCDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBADgj/duR2dPE
# PasW6bcwXzFUp0SSiEA5tt4+tD7R+vltGKaPP2xWQpP/uByPg4xwKVJgb4h1foyn
# cRiwsdZ+O/B/MWh5kT7JNt0GP/VUdlBG4KbDpCp5UJNvDaedLucHGdZ32hlds9Sm
# oRrAfkOpdBpYWBH0DgpZUr8i9dUMyPU+U8IRLU/cmic1t2GSSTPj2sm4o6blvt78
# EfyWioCZc5dFzbbLFZVMxasSnimyWa/x5PtWhjxf+N0phM9URex+YttUVyrMy4Hy
# 8UZ9TJaxZE5LzCCruVBh9ZxiqHs3KagBNf7BZgrfNYbtpFyI8ZQDPOdd1/5oe0ha
# dAs1rkcWZJeSJqTd9K6mtZhmIeG5iMTXqGugClwEemb7xL+Q2qGb1aNBf7YHGdi/
# 4l6PLqWpOLx8sEtLTr1ZdXD+m1/khX4W1iXfga9Wh6DfVShSZVVl7VINQmSb10Nd
# zyX+oENiIAhPYIKw9PK31cD0lW4fF0/refsKG9YA7/jtBG4IOxSUUmhbDIHCXuN5
# ilpFUy1C3SK4kwYaOARolfVD/aPyxdRG9Nx4scMP2Kla3T3ZkNYxByINGaEc0U5f
# V2eMG+T+TVQxyD33uPmhjOcCdKkm+WD/gE/dpUTSH9gfYqCwptTg1dkcCMlePZKW
# qjULXXkIbqoFloWQzxbq89kKbmqdJ7M6MIIHcTCCBVmgAwIBAgITMwAAABXF52ue
# AptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgz
# MjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxO
# dcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQ
# GOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq
# /XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVW
# Te/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7
# mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De
# +JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM
# 9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEz
# OUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2
# ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqv
# UAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q
# 4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcV
# AgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXS
# ZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
# cnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1
# AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaA
# FNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8y
# MDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAt
# MDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8
# qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7p
# Zmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2C
# DPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BA
# ljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJ
# eBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1
# MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz
# 138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1
# V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLB
# gqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0l
# lOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFx
# BmoQtB1VM1izoXBm8qGCA1AwggI4AgEBMIH5oYHRpIHOMIHLMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1l
# cmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzMwMy0w
# NUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wi
# IwoBATAHBgUrDgMCGgMVAAtsSBlmfJgdcnUMZvl8aOmVem25oIGDMIGApH4wfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDupbM2
# MCIYDzIwMjYxMTE2MTY1MjA2WhgPMjAyNjExMTcxNjUyMDZaMHcwPQYKKwYBBAGE
# WQoEATEvMC0wCgIFAO6lszYCAQAwCgIBAAICCI4CAf8wBwIBAAICE1AwCgIFAO6n
# BLYCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAweh
# IKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAWgnUlYJlQUKIH4hYfq3m
# QzPq8Flcdyu0SruIE08mqpfUn6AhGrAseOEN5ghiQT4UUBUGz7i9E6iUWbPwAv42
# Jnd5C2Rpid5GM8Rz0X1f0B6VqolXmI6nBC/nafbbM+/K6NRJsufyEc3fgnqfZ+nM
# JorEpwuOmI1i4e9wlPuWsZvtZkY3l9zVI1F7o1fVPJvN7K6xLrrCUqiRcoa1KOJi
# xOFjLjoz4fJ6aUbpfLbyEBf45dFicDloYiacDBv5qCsXKFPy+mjCyWs9wI9Mokff
# dgYfm4TG45WhEKVjXyUXgwGda4XXDSfTqXAgOom0NaHcJBNhnZJL0TWymKRH4ryw
# xjGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMz
# AAACITPANfvSDyGkAAEAAAIhMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0B
# CQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIFgxDaOTllyFUmcTKs13
# si2d1QxdbtixD7pFfOwWKDiiMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQg
# AO8hB58VVRrgEnLwhnLAwC+YZIp1RWoSbL0D748KPUQwgZgwgYCkfjB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiEzwDX70g8hpAABAAACITAiBCBy
# EoSpNBPnDmLJnB/SnFjkbQTX2o7fazE07uE8zOYn7jANBgkqhkiG9w0BAQsFAASC
# AgCg9MoMFHVzYf3q9pKIqxfoCexgyfyk+m2D2xJy12FjTXuM9VqDq0tcqm8bODoT
# P67Mwf0eYqmIGUfZeLr2Euwm0OyGnjYut5l1yzt8KAcNSK3J862r5ywlxKsaSP17
# nH3TMeCsBaC5tDJI6UcbNbkZAELJoDCNYzxuWw+w8wZNeanBI3kwQGhgLHPVfD8T
# OnoRJk5Dnk4bc5g4fCTsgTeMBlp9dQq42x3W8Xlm9C83B86Y8LgVxdnOeeunTPqL
# BjBiF1xCRv+HoTl64VyLfXQLLlfqYDyf/+BseSty+2hH64egIg4d/qxIzHzTPoKv
# W4XynsJBZBrtIK21JOYCgq+lKZi1153i5EwLgcWbK2nwIwncyuYf4IV1C9ooPboS
# To3l4BNFw1V80f3bSu1lNsp6f3zGbiu5SjZ19FdsBv2bo0VKFl/y9BusmsxMdrME
# vfhXCnJPax4VorNyO5p5e/zKJaMpHxrs1nrJv+bVKOQps7e429oLMvFhOx/kawar
# vErYeEp9KVRu+olJzqJgJ8XalJ0Rd5NQV4x5YbTP8uk/B17JGrXBDti0BokKsKDi
# QFPxmUc3Sbee7FynPyazqeJuxit8zCztCCxa1Vlr9ikob1hXcJDVvfjw1A7w0gJt
# ipMjzbN7i52yN9K6USKJq/XUEZfNvBJt/4zuqAUCDAobKg==
# SIG # End signature block
