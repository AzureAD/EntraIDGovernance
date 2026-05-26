<#
.SYNOPSIS
    Configures Entra ID as the source of authority over select AD objects. 

.DESCRIPTION
    Creates a Service Connection Point (SCP) in Active Directory representing the
    CloudSync SOA policy.  

    The script must be run on a machine where the Azure AD Connect Provisioning Agent
    is installed. Domain Admin credentials are required to create the objects in AD.

.PARAMETER EnforcementMode
    The enforcement mode for the policy. Valid values are 'Enforced' or 'Audit'.

.PARAMETER Credential
    Domain Admin credentials in the format DOMAIN\Username.

.EXAMPLE
    .\Set-CloudSyncSOAPolicy.ps1 -EnforcementMode Enforced -Credential (Get-Credential)

.EXAMPLE
    $cred = Get-Credential -UserName "contoso.com\Administrator" -Message "Enter Domain Admin credentials"
    .\Set-CloudSyncSOAPolicy.ps1 -EnforcementMode Audit -Credential $cred -Verbose
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "The enforcement mode for the policy. Valid values are 'Enforced' or 'Audit'.")]
    [ValidateSet("Enforced", "Audit")]
    [string] $EnforcementMode,

    [Parameter(Mandatory = $true, HelpMessage = "Domain Admin credentials (format: DOMAIN\Username).")]
    [System.Management.Automation.PSCredential] $Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PolicyName      = "Cloud"
$AgentServiceName = "AADConnectProvisioningAgent"

# ---------------------------------------------------------------------------
# Step 1: Resolve GMSA SAM account name from the installed service
# ---------------------------------------------------------------------------
Write-Verbose "Retrieving service account for '$AgentServiceName'..."

$service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$AgentServiceName'"
if ($null -eq $service) {
    throw "Service '$AgentServiceName' not found. Ensure the Azure AD Connect Provisioning Agent is installed on this machine."
}

$gmsaFullName = $service.StartName
Write-Verbose "Service start name: $gmsaFullName"

# Strip domain prefix if present (e.g., "DOMAIN\pGMSA_12345678$" -> "pGMSA_12345678$")
$gmsaSamAccountName = if ($gmsaFullName -match '\\') { $gmsaFullName.Split('\')[1] } else { $gmsaFullName }

# Ensure trailing '$' required for a GMSA SAM account name
if (-not [string]::IsNullOrWhiteSpace($gmsaSamAccountName) -and -not $gmsaSamAccountName.EndsWith('$')) {
    $gmsaSamAccountName = $gmsaSamAccountName + '$'
}

# ---------------------------------------------------------------------------
# Step 2: Parse Domain Admin credential
# ---------------------------------------------------------------------------
$username = $Credential.UserName
if ($username -notmatch '\\') {
    throw "Credential username must be in 'DOMAIN\Username' format (e.g., 'contoso.com\Administrator')."
}

$domainName = $username.Split('\')[0]
$password   = $Credential.GetNetworkCredential().Password

Write-Verbose "Domain: $domainName | GMSA SAM: $gmsaSamAccountName"

# ---------------------------------------------------------------------------
# Step 3: Look up SIDs via System.DirectoryServices.AccountManagement
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.DirectoryServices.AccountManagement

$ctx      = $null
$gmsaSid  = $null

try {
    $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
        [System.DirectoryServices.AccountManagement.ContextType]::Domain,
        $domainName,
        $username,
        $password
    )

    # GMSA SID (required — throws if not found)
    if ([string]::IsNullOrWhiteSpace($gmsaSamAccountName)) {
        throw "GMSA service account name is not configured. Please ensure the GMSA is created during installation."
    }

    $gmsaPrincipal = [System.DirectoryServices.AccountManagement.Principal]::FindByIdentity(
        $ctx,
        [System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,
        $gmsaSamAccountName
    )

    if ($null -eq $gmsaPrincipal) {
        throw "GMSA '$gmsaSamAccountName' not found in domain '$domainName'. The GMSA account is required for the SOA policy."
    }

    $gmsaSid = $gmsaPrincipal.Sid.ToString()
    Write-Verbose "Found GMSA '$gmsaSamAccountName' with SID '$gmsaSid'."
}
finally {
    if ($null -ne $ctx) { $ctx.Dispose() }
}

# ---------------------------------------------------------------------------
# Step 4: Create the SCP in Active Directory
# ---------------------------------------------------------------------------
Write-Verbose "Creating SOA policy '$PolicyName' (mode: $EnforcementMode) on domain '$domainName'..."

$rootDse              = $null
$systemContainer      = $null
$soaPoliciesContainer = $null
$scp                  = $null

try {
    $rootDse = New-Object System.DirectoryServices.DirectoryEntry(
        "LDAP://$domainName/RootDSE",
        $username,
        $password
    )

    $domainDn = $rootDse.Properties["defaultNamingContext"].Value
    if ([string]::IsNullOrEmpty($domainDn)) {
        throw "Could not read defaultNamingContext from domain '$domainName'."
    }

    $systemContainer = New-Object System.DirectoryServices.DirectoryEntry(
        "LDAP://CN=System,$domainDn",
        $username,
        $password
    )

    # Get or create the CN=SOA-Policies container
    try {
        $soaPoliciesContainer = $systemContainer.Children.Find("CN=SOA-Policies", "container")
        Write-Verbose "CN=SOA-Policies container already exists."
    } catch [System.Runtime.InteropServices.COMException] {
        $soaPoliciesContainer = $systemContainer.Children.Add("CN=SOA-Policies", "container")
        $soaPoliciesContainer.Properties["description"].Value = "Container for Service Ownership Assertion policies"
        $soaPoliciesContainer.CommitChanges()
        Write-Verbose "Created CN=SOA-Policies container under CN=System."
    }

    # Check whether the policy SCP already exists
    try {
        $existing = $soaPoliciesContainer.Children.Find("CN=$PolicyName", "serviceConnectionPoint")
        if ($null -ne $existing) { $existing.Dispose() }
        Write-Warning "SOA policy '$PolicyName' already exists. No changes were made."
        return
    } catch [System.Runtime.InteropServices.COMException] {
        # Policy does not yet exist — proceed with creation
    }

    # Create the policy SCP
    $scp = $soaPoliciesContainer.Children.Add("CN=$PolicyName", "serviceConnectionPoint")
    $scp.Properties["serviceBindingInformation"].Value = "CloudSync"
    [void] $scp.Properties["keywords"].Add($EnforcementMode)
    [void] $scp.Properties["msDS-Settings"].Add($gmsaSid)

    $scp.CommitChanges()

    Write-Output "SOA policy '$PolicyName' created successfully. GMSA SID: $gmsaSid"
}
finally {
    if ($null -ne $scp)                  { $scp.Dispose() }
    if ($null -ne $soaPoliciesContainer) { $soaPoliciesContainer.Dispose() }
    if ($null -ne $systemContainer)      { $systemContainer.Dispose() }
    if ($null -ne $rootDse)              { $rootDse.Dispose() }
}