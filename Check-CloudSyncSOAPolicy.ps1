<#
.SYNOPSIS
    Retrieves Cloud Sync SOA Policy objects and the provisioning agent gMSA from Active Directory.

.DESCRIPTION
    Queries the current domain for:
      - The SOA-Policies container under CN=System
      - The Cloud object under CN=SOA-Policies,CN=System
      - The provisioning agent gMSA under CN=Managed Service Accounts
    Domain is detected automatically. Reports an error for each object not found.

.NOTES
    Requires the ActiveDirectory PowerShell module and appropriate read permissions.
#>

#Requires -Modules ActiveDirectory

# --- Detect domain automatically ---
try {
    $Domain     = Get-ADDomain -ErrorAction Stop
    $DomainDN   = $Domain.DistinguishedName   # e.g. DC=contoso,DC=lab
    $DomainName = $Domain.DNSRoot             # e.g. contoso.lab
}
catch {
    Write-Error "Failed to retrieve domain information. Ensure the ActiveDirectory module is available and you are joined to a domain.`n$($_.Exception.Message)"
    exit 1
}

Write-Host "`nDomain detected: $DomainName  ($DomainDN)" -ForegroundColor Cyan

# --- Build distinguished names dynamically ---
$SOAPoliciesContainerDN  = "CN=SOA-Policies,CN=System,$DomainDN"
$CloudSyncSOAPolicyDN    = "CN=Cloud,CN=SOA-Policies,CN=System,$DomainDN"
$ProvAgentgMSADN         = "CN=provAgentgMSA,CN=Managed Service Accounts,$DomainDN"

$Results = [ordered]@{}

# --- Helper: query a single AD object by DN ---
function Get-ADObjectByDN {
    param(
        [string]$DistinguishedName,
        [string]$Label
    )

    try {
        $obj = Get-ADObject -Identity $DistinguishedName `
                            -Properties * `
                            -ErrorAction Stop
        Write-Host "`n[FOUND] $Label" -ForegroundColor Green
        return $obj
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Warning "[NOT FOUND] $Label`n  DN: $DistinguishedName"
        return $null
    }
    catch {
        Write-Error "[ERROR] $Label`n  DN: $DistinguishedName`n  $($_.Exception.Message)"
        return $null
    }
}

# --- Query each object ---
$Results['SOA-Policies Container'] = Get-ADObjectByDN -DistinguishedName $SOAPoliciesContainerDN `
                                                       -Label "SOA-Policies Container  ($SOAPoliciesContainerDN)"

$Results['CloudSyncSOAPolicy']     = Get-ADObjectByDN -DistinguishedName $CloudSyncSOAPolicyDN `
                                                       -Label "Cloud Object  ($CloudSyncSOAPolicyDN)"

$Results['provAgentgMSA']          = Get-ADObjectByDN -DistinguishedName $ProvAgentgMSADN `
                                                       -Label "Provisioning Agent gMSA  ($ProvAgentgMSADN)"

# --- Display results ---
Write-Host "`n===== Summary =====" -ForegroundColor Cyan

foreach ($key in $Results.Keys) {
    $obj = $Results[$key]
    if ($null -ne $obj) {
        Write-Host "`n[$key]" -ForegroundColor Yellow
        $obj | Select-Object Name, ObjectClass, DistinguishedName, WhenCreated, WhenChanged |
            Format-List
    }
    else {
        Write-Host "`n[$key]  --> NOT FOUND or ERROR" -ForegroundColor Red
    }
}

# --- gMSA-specific detail (if found) ---
$gMSA = $Results['provAgentgMSA']
if ($null -ne $gMSA -and $gMSA.ObjectClass -eq 'msDS-GroupManagedServiceAccount') {
    Write-Host "`n[gMSA Detail]" -ForegroundColor Yellow
    Get-ADServiceAccount -Identity $ProvAgentgMSADN -Properties * -ErrorAction SilentlyContinue |
        Select-Object Name, SamAccountName, DNSHostName, Enabled,
                      PrincipalsAllowedToRetrieveManagedPassword,
                      ServicePrincipalNames |
        Format-List
}

# --- SOA Policy attributes (if found) ---
$soaPolicy = $Results['CloudSyncSOAPolicy']
if ($null -ne $soaPolicy) {
    Write-Host "`n[Cloud Attributes]" -ForegroundColor Yellow
    $soaPolicy | Select-Object -Property * | Format-List
}

# --- SID Authorization Check ---
# Verify that the provAgentgMSA SID is present in the msDS-Settings of Cloud.
# msDS-Settings stores the authorized SIDs that are permitted to write cloud-owned objects.
Write-Host "`n===== SID Authorization Check =====" -ForegroundColor Cyan

if ($null -eq $gMSA) {
    Write-Warning "Skipping SID check: provAgentgMSA was not found."
}
elseif ($null -eq $soaPolicy) {
    Write-Warning "Skipping SID check: Cloud policy was not found."
}
else {
    # Retrieve the SID of the gMSA as a string
    $gMSASid      = $gMSA.objectSid.Value
    $msDsSettings = @($soaPolicy.'msDS-Settings')   # may be a single value or an array

    Write-Host "  provAgentgMSA SID : $gMSASid"
    Write-Host "  msDS-Settings     : $($msDsSettings -join ', ')"

    if ($msDsSettings -contains $gMSASid) {
        Write-Host "`n  [PASS] The gMSA SID is present in msDS-Settings. Cloud Sync is authorized to write cloud-owned objects." -ForegroundColor Green
    }
    else {
        Write-Host "`n  [FAIL] The gMSA SID is NOT present in msDS-Settings." -ForegroundColor Red
        Write-Host "         Cloud Sync will be blocked from writing objects protected by this SOA policy." -ForegroundColor Red
        Write-Host "         Expected SID  : $gMSASid" -ForegroundColor Red
        Write-Host "         Current value : $($msDsSettings -join ', ')" -ForegroundColor Red
    }
}

# --- Policy Mode Check (keywords attribute) ---
# The keywords attribute controls the enforcement mode of the SOA policy.
# Expected values: "Enforced" (blocks writes) or "Audit" (logs only, allows writes).
# Multiple keyword values is unexpected and may indicate misconfiguration.
Write-Host "`n===== Policy Mode (keywords) =====" -ForegroundColor Cyan

if ($null -eq $soaPolicy) {
    Write-Warning "Skipping policy mode check: Cloud policy was not found."
}
else {
    $keywords = @($soaPolicy.keywords)

    if ($keywords.Count -eq 0 -or ($keywords.Count -eq 1 -and [string]::IsNullOrWhiteSpace($keywords[0]))) {
        Write-Host "  [WARN] keywords attribute is empty. Policy mode is indeterminate." -ForegroundColor Yellow
    }
    elseif ($keywords.Count -gt 1) {
        Write-Warning "Multiple values found in keywords attribute. This is unexpected and may indicate misconfiguration."
        Write-Host "  keywords values:" -ForegroundColor Yellow
        $keywords | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    }
    else {
        $mode = $keywords[0].Trim()
        Write-Host "  keywords : $mode"

        switch ($mode) {
            'Enforced' {
                Write-Host "`n  [ENFORCED] The SOA policy is in enforcement mode." -ForegroundColor Red
                Write-Host "             AD will BLOCK any modification to protected objects by unauthorized callers." -ForegroundColor Red
                Write-Host "             Event ID 3098 will be logged on the DC for each blocked write." -ForegroundColor Red
            }
            'Audit' {
                Write-Host "`n  [AUDIT] The SOA policy is in audit-only mode." -ForegroundColor Yellow
                Write-Host "          AD will LOG but ALLOW modifications to protected objects by unauthorized callers." -ForegroundColor Yellow
                Write-Host "          Event ID 3097 will be logged on the DC for each would-be-blocked write." -ForegroundColor Yellow
            }
            default {
                Write-Host "`n  [UNKNOWN] Unrecognized keywords value: '$mode'" -ForegroundColor Magenta
                Write-Host "             Expected 'Enforced' or 'Audit'." -ForegroundColor Magenta
            }
        }
    }
}

# --- DC Diagnostics Registry Check ---
# This check only applies when the script is run directly on a Domain Controller.
# The registry value "2 Security Events" under NTDS\Diagnostics controls whether
# Event IDs 3095, 3097, and 3098 (SOA policy audit/enforcement events) are logged.
Write-Host "`n===== DC Diagnostics: SOA Event Logging =====" -ForegroundColor Cyan

$isDC = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).DomainRole -ge 4

if (-not $isDC) {
    Write-Host "  (Skipped) This machine is not a Domain Controller. Run on a DC to check the diagnostics registry key." -ForegroundColor DarkGray
}
else {
    $regPath  = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Diagnostics'
    $regName  = '2 Security Events'

    try {
        $regValue = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop).$regName

        Write-Host "  Registry : $regPath"
        Write-Host "  Value    : '$regName' = $regValue"

        if ($regValue -ge 1) {
            Write-Host "`n  [ENABLED] SOA policy diagnostic logging is ON (value: $regValue)." -ForegroundColor Green
            Write-Host "            Event ID 3095 (policy load), 3097 (audit block), and 3098 (enforced block)" -ForegroundColor Green
            Write-Host "            will be written to the Directory Service event log." -ForegroundColor Green
        }
        else {
            Write-Host "`n  [DISABLED] SOA policy diagnostic logging is OFF (value: $regValue)." -ForegroundColor Yellow
            Write-Warning "Set '$regName' to 1 under $regPath to enable logging of SOA audit and enforcement events (IDs 3095, 3097, 3098)."
        }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Host "  [NOT SET] The registry value '$regName' does not exist under $regPath." -ForegroundColor Yellow
        Write-Warning "SOA policy diagnostic logging is effectively disabled. Set '$regName' = 1 to enable Event IDs 3095, 3097, and 3098."
    }
    catch {
        Write-Error "Failed to read registry value '$regName' from $regPath`n$($_.Exception.Message)"
    }
}

