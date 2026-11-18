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

    # 4. Get and print the members of each service.
    #    Requests run sequentially. JSON output includes nested properties.
    foreach ($service in $servicesResponse.value)
    {
        if ([string]::IsNullOrWhiteSpace($service.serviceName))
        {
            throw 'A service in the list did not contain a serviceName.'
        }

        $serviceName = [Uri]::EscapeDataString($service.serviceName)
        $requestParameters.Uri = '{0}/{1}/servicemembers?api-version=2014-01-01' -f $servicesUri, $serviceName
        Write-Host "`nGetServiceMembers: GET $($requestParameters.Uri)"
        $membersResponse = Invoke-RestMethod @requestParameters
        if ($null -eq $membersResponse -or $null -eq $membersResponse.PSObject.Properties['value'])
        {
            throw "The service members response for '$($service.serviceName)' did not contain the expected value collection."
        }

        $membersResponse | ConvertTo-Json -Depth 50
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
# MIIouwYJKoZIhvcNAQcCoIIorDCCKKgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDVIC7roJyKHeXv
# SScMtkcWJwTeYTOAEZMsIujcBjSLsqCCDcMwggatMIIElaADAgECAhMzAAAA0wKI
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
# TjCCGkoCAQEweTBiMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMTMwMQYDVQQDEypBenVyZSBSU0EgUHVibGljIFNlcnZpY2VzIENv
# ZGUgU2lnbmluZyBQQ0ECEzMAAADTAojYab3fAgkAAAAAANMwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IF29iTfVI2dvCVQsFs/aaGMEAS9sa4dXGydMr/0IkXg5MEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggGAsOXZBMl/cdkHQT6ZmKSlu+2YBFFnik1z
# jREkZs4xNnrVhDu//05mX+xI/J7suM+bPfJ1Bf9vT8J/tdcu5+toPuff8EUY66zc
# wtBrRDJd5V89auXM6jUtvZBpJhVvSz1nmir0uLlswGlLx0/hLxdSRsr/QfW9PV+8
# L6iGox8Owkm37Z/5ax2XcsxQavBXds+/aEvlGpc1ALDL+tFPZkcqPGwVv6cmjPop
# YOOA4b2i8Jthw4ZAynXYonkcXPYRVzcEQmz4FvZzjeneGcTeKUaRhgJXK7L02VJM
# 39UJLPr+3KICe7o9s86/FL9wrDe2UQvLNWjzGyyeSlamnP0in0VZJdqGmNUtM6n3
# OCzQsJS3V17SNm0EOLELy6jEmby0lWbSBrZdMyc0yI4UGj579xeEoQO6PjYYjsy7
# Yw8EIaDHH4oAVHHPubmVzcfHtjACgc5dekgOzUaFqgg8ST16Vyd6NVGa8wlhaJ/W
# /sqgy2r1FYoPTyHPDiizp9E/WKyMmgNYoYIXkzCCF48GCisGAQQBgjcDAwExghd/
# MIIXewYJKoZIhvcNAQcCoIIXbDCCF2gCAQMxDzANBglghkgBZQMEAgEFADCCAVEG
# CyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIGGVfSqrtUE2tXGuuJRWM0FLnn0E5X51LbtBQv+I4QTkAgZq80vn
# azQYEjIwMjYxMTE3MDEwOTMwLjYxWjAEgAIB9KCB0aSBzjCByzELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFt
# ZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkEwMDAt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oIIR6jCCByAwggUIoAMCAQICEzMAAAIruwBQ/007mqEAAQAAAiswDQYJKoZIhvcN
# AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjYwMjE5MTk0
# MDExWhcNMjcwNTE3MTk0MDExWjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9u
# czEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkEwMDAtMDVFMC1EOTQ3MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAl95oujg97MlKkJuEKoJKyj23LCv0Md32HLS/PlTN
# bjmN26KIuRscGrk4EH+iRRyE06MUu4I6ipSvDhS8y+lE5dI8RCubeg7jnICV3b7r
# YpqE5TktAt5MiE1wQF6I/4KeoUUfc+lkYqdSrZIpW93SVwo0Kk/T9grro6/lc/K/
# mfow5dPY4v4nP+Bt+K95lcI7P/xp8fT7t9VfK1xYnDYgM8abm2sKW3fKan85Vk9r
# 5xt5BfZejIkRG7yd1xy1MB0LIdLf060hcf7P8gqqSVmCeqApRu9Lb7BR9GkT/MAe
# HD/whWtiC75NuotznCQZfqaiox00gcvZr8EzxA5Z83KNDbfEeqUj012YAbLHB4aC
# nwtFkJjs2NpHl2wJkU3GTMl8+b/wCW5qCNMtOwWs77eTZF3XRvUxK0FsLbBciCqx
# JQ4Fnx3gqE7tcLtnIg93Su9s93GtoM6BA8U9o/QVyFCmok803UD0bADGjt3VNM2h
# sDDJcLUicg4deGBIGaFLub0vDLoDKnazY6Yci+ucioY6QFm4WJCBzv9LmY7vebT/
# M2TalyEYeLXX1hyTwE5/a/nMZMrodsdFS3X8dZZivV9zYx9DbYALOSQf8DpZMrrn
# cZhU31lckay9+4rKTmfGjwBYL8kenDU5BqZBaN+SUY3IjZmYlOKk/VLcvleYLnRZ
# NY8CAwEAAaOCAUkwggFFMB0GA1UdDgQWBBQ+Fo7kE1CW7W3d45r2ZLtBWdnlNjAf
# BgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQ
# hk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQl
# MjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBe
# MFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2Nl
# cnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAM
# BgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQE
# AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAzvwirHIhDPJK9X6h+E5X0+uhDaE48V8P
# NdKchKtD3a4C8H4E98ftYM+wkB7VHXr6jEOah8gy4ZuqU/ddQmJBjfuoPjFO3zGE
# 6+nd0sYnicASKFpH0eIO0orRszClOOuShGHo33XaFIKLwv8XEaWgCzuad/wNuPAc
# oSYjLbQUDQ7bE/x2ghcERQlEW8v3/HNZJMvBfMZAlxc/vzLWeXdZVhY8DiNoHmR1
# qvV4oQzoHnuZ0tpKKOVep/FxtttFE3r1X/qYJqSB+9Vyg1SGExhmSbOsj5Xydml6
# sNTBODUeqJDbGNz9TN9R+gzGEXyRjQTXqefeZFxod2MwN3AosoPo5iefIf307454
# CKblBXzg6Q4xcdInNWKCwDcYQhd0YUvamDOyuNDRISrIWLmgJCBtlwSmIoN6/9P2
# 9LI74wcLOeQGKJzJtwPKnF/+pPVX3NJr/XbaJx7lhnwNm/qhNqqQp4cxm3Qx6u4j
# kmRMNNZzbqQDH9XONZPSKE0Ns94sOsOGWaCzsoOEyjG6dZK6U+La4qf8t9Ar+ZIc
# qggzaml0KQZDmDjfC4LaEN2plTl+4seY3a58f71MU1EooF761nS+1JPJKZktM7aN
# k6Mu2k+aAcwk734/YifwTfxNb4RQZISQr2ez1b7DEp005pMdhWpdpVZM7bgCOOHw
# /7siyXWjEEswggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqG
# SIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkg
# MjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4X
# YDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTz
# xXb1hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7
# uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlw
# aQ3KNi1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedG
# bsoy1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXN
# xF803RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03
# dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9
# ahhaYQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5
# UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReT
# wDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZ
# MBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8
# RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAE
# VTBTMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAww
# CgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQD
# AgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb
# 186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoG
# CCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZI
# hvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9
# MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2Lpyp
# glYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OO
# PcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8
# DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA
# 0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1Rt
# nWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjc
# ZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq7
# 7EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJ
# C4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328
# y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYID
# TTCCAjUCAQEwgfmhgdGkgc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMx
# JzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpBMDAwLTA1RTAtRDk0NzElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# Caw/dMpB6aP9ABm+5ZsL7ArakTmggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO6lsmIwIhgPMjAyNjExMTYxNjQ4
# MzRaGA8yMDI2MTExNzE2NDgzNFowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA7qWy
# YgIBADAHAgEAAgIYRDAHAgEAAgITezAKAgUA7qcD4gIBADA2BgorBgEEAYRZCgQC
# MSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqG
# SIb3DQEBCwUAA4IBAQAoyfAOPqIympCfPVOSmzKDSJ9tDyixSDnbClA+eXgqVaQl
# 3W4yn1y6ZXte90IpxbWd6TSaReqi7Mg7iaVFTK/LmRQElOVMzzhlp30ylYcc2qoV
# S6Gc2RWfNhM38qeagHacrbKNcT7C82MxsebjUJkc0ZVhmwD5403bAPvumMjvFRYG
# 6TfVyETSwMISvhsBNoZSoZV4EeVJVIpkhh/qrdLJLW1v9jxKDjGYefgz7PHq3ERT
# U/D2WFwyMFBhPFhWQDQphtt1bWDRlM7JELpS6wSnDFgvcXLSHN2gf8c0kqXyJRkB
# Zws53IlHz/sEU3jpgnYmnF7JPtgCHf7sCfhzZFaHMYIEDTCCBAkCAQEwgZMwfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIruwBQ/007mqEAAQAAAisw
# DQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAv
# BgkqhkiG9w0BCQQxIgQgbjFidmdeBkQhqSZuXSfEc4JOO76+alXx/y+93lyPU9Uw
# gfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCByDiP0P5BX7WAPjNjmPtQcd2ow
# Q+v1gwLT09rxZL9uUjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwAhMzAAACK7sAUP9NO5qhAAEAAAIrMCIEINstb/31OpdtfyoZvKfr7uVy9TTh
# 1e9V6Zb3/xshbpanMA0GCSqGSIb3DQEBCwUABIICABJ3iOLLlK5h8fddw+lmyofY
# QZ54WMoLxK8Ctb+GtNGwM7//KEAtSvlya1oPLdWNtw/w9UuE0Dbbb9l3cEUsYD7V
# gPmg7nRF1fISAzdQNts01ZdoIhhpd+RpylpQhqbDcC2JK+IAf8oHagVbEzWymQqN
# NMDvfnVmtfW7oNCFGM4ya+YVnsm5OdCUhCDcHNpwc8k0tq6Ar1K0qepOwQ/IXdQX
# YArRKEH5kClEjuk9OTL9/WVApSrAmaLA6v7PeXO3kjxjEQGtuUy6OK+JGsv44SE3
# dDFjHbz2wQjXrC94AmEVP0HV0j30wGTeoTWqTQ6vhAkXWZPeZWnWR9ZFdbRSM4hs
# kGjfUbyqUr5P6/eO4eVA6emxTatdCX6uFY6ydCzhg9q3P57ryDnzKjhJZ8DDhGjI
# fkBOIWvALlfEUcEVbst2+zDAWGHG5jGX77zmD/44gGDc9qsTRRKxhptmWDr2YOb7
# sVwT2ouXqJfA4vNOTecIC/B97LJSqcXlz3uUefKswKKQrlkjwnBaBdb5AwY9Jo+C
# p2EbRMZEHIAB7gyZUGMrvmnlfrkjcxFnahAj7pToJfOnMKns70ElbR6hKqCASQQK
# mifjHgf0o/a+OSsxX1hC/LbquhOvvKdVFCnZc/N0D0xORCwsgjS/0xGzIAD/rdVn
# 5M+mKMmzqS8e6bVnasfm
# SIG # End signature block
