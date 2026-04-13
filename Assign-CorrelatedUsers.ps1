<#
.SYNOPSIS
    Assigns correlated-but-unassigned users from an identity correlation report
    to an enterprise application, with CSV-based routing to access packages.

.DESCRIPTION
    1. Lists correlation reports for a service principal and picks the latest.
    2. Retrieves identities with status 'correlatedNotAssigned' and 'correlatedAssigned'.
    3. Assigns correlatedNotAssigned users to the enterprise application via appRoleAssignedTo.
    4. (Optional) Routes ALL correlated users (both assigned and not-yet-assigned)
       to access packages based on rules in a CSV file.
       Rules match against targetIdentity.details.Properties (the SCIM property bag).
       ALL matching rule groups result in assignment (a user can get multiple packages).

    Rules CSV columns:
        RuleGroup       - rows sharing the same group number are AND-ed together.
                          Different groups are evaluated independently.
        PropertyName    - key in the target property bag (e.g. title, userType,
                          displayName, userName, name.givenName).
                          Use "source.userPrincipalName" to match on
                          sourceIdentity.matchingProperty.value.
        Operator        - eq | ne | contains | startswith | endswith | regex
        Value           - the value to compare against (case-insensitive)
        AccessPackageId - the access package to assign when the group matches
        PolicyId        - the assignment policy for that access package

.PARAMETER ServicePrincipalId
    The object ID of the service principal (enterprise application).

.PARAMETER AppRoleId
    The app role ID to assign. Defaults to the "Default Access" role (all-zeros GUID).

.PARAMETER RulesFile
    Path to a CSV file with routing rules. See description for column format.

.PARAMETER AccessPackageId
    (Optional) Fallback access package ID when no rules match a user
    (requires -FallbackBehavior UseFallback). Also used when -RulesFile is
    not provided (simple mode, same as original script).

.PARAMETER PolicyId
    (Optional) Fallback/simple-mode assignment policy ID.

.PARAMETER FallbackBehavior
    What to do when no rule matches a user (only relevant with -RulesFile).
    - Skip         : do not assign an access package (default).
    - UseFallback  : assign to -AccessPackageId / -PolicyId.

.PARAMETER SkipAppRoleAssignment
    If specified, skips step 4 (enterprise app role assignment). Useful when
    users are already assigned to the app and you only want to manage access packages.

.PARAMETER OutputFile
    (Optional) Path to a CSV file where results will be exported for audit trail.

.PARAMETER DryRun
    Lists what would be done without making changes.

.EXAMPLE
    # Simple mode (no rules) - same behavior as original script
    .\Assign-CorrelatedUsers.ps1 -ServicePrincipalId "7A22..." `
        -AccessPackageId "a914..." -PolicyId "2264..."

.EXAMPLE
    # CSV rules with fallback
    .\Assign-CorrelatedUsers.ps1 -ServicePrincipalId "7A22..." `
        -RulesFile ".\access-package-rules.csv" `
        -AccessPackageId "fallback-pkg" -PolicyId "fallback-pol" `
        -FallbackBehavior UseFallback -DryRun

.EXAMPLE
    # CSV rules, skip unmatched users
    .\Assign-CorrelatedUsers.ps1 -ServicePrincipalId "7A22..." `
        -RulesFile ".\access-package-rules.csv" -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ServicePrincipalId,

    [Parameter()]
    [string]$AppRoleId = "00000000-0000-0000-0000-000000000000",

    [Parameter()]
    [string]$RulesFile,

    [Parameter()]
    [string]$AccessPackageId,

    [Parameter()]
    [string]$PolicyId,

    [Parameter()]
    [ValidateSet("Skip", "UseFallback")]
    [string]$FallbackBehavior = "Skip",

    [Parameter()]
    [switch]$SkipAppRoleAssignment,

    [Parameter()]
    [string]$OutputFile,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Results log
# ---------------------------------------------------------------------------

$resultsLog = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-ResultEntry {
    param(
        [string]$UserId,
        [string]$DisplayName,
        [string]$Status,
        [string]$Step,
        [string]$Action,
        [string]$AccessPackageId,
        [string]$PolicyId,
        [string]$Details
    )
    $resultsLog.Add([PSCustomObject]@{
        Timestamp       = (Get-Date -Format 'o')
        UserId          = $UserId
        DisplayName     = $DisplayName
        CorrelationStatus = $Status
        Step            = $Step
        Action          = $Action
        AccessPackageId = $AccessPackageId
        PolicyId        = $PolicyId
        Details         = $Details
    })
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Invoke-GraphRequest {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][object]$Body
    )
    $params = @{
        Method = $Method
        Uri    = $Uri
    }
    if ($Body) {
        $params.Body        = ($Body | ConvertTo-Json -Depth 10)
        $params.ContentType = "application/json"
    }
    Invoke-MgGraphRequest @params
}

function Get-AllPages {
    param([Parameter(Mandatory)][string]$Uri)
    $results = @()
    $currentUri = $Uri
    while ($currentUri) {
        $response = Invoke-GraphRequest -Method GET -Uri $currentUri
        if ($response.ContainsKey('value') -and $response.value) {
            $results += $response.value
        }
        $currentUri = if ($response.ContainsKey('@odata.nextLink')) { $response.'@odata.nextLink' } else { $null }
    }
    return $results
}

function Get-IdentityUserId {
    param([Parameter(Mandatory)]$Identity)
    $uid = $Identity.sourceIdentity.anchor.value
    if (-not $uid) { $uid = $Identity.sourceIdentity.id }
    if (-not $uid) { $uid = $Identity.id }
    return $uid
}

function Get-IdentityDisplayName {
    param([Parameter(Mandatory)]$Identity)
    # Try to pull displayName from the target property bag
    $props = Get-TargetProperties -Identity $Identity
    if ($props -and $props.ContainsKey('displayName')) {
        return ($props['displayName'] | Select-Object -First 1)
    }
    $dn = $Identity.sourceIdentity.displayName
    if (-not $dn) { $dn = $Identity.displayName }
    if (-not $dn) { $dn = Get-IdentityUserId -Identity $Identity }
    return $dn
}

function Get-TargetProperties {
    param([Parameter(Mandatory)]$Identity)
    $raw = $Identity.targetIdentity.details.Properties
    if (-not $raw) { return @{} }
    try { return ($raw | ConvertFrom-Json -AsHashtable) }
    catch { return @{} }
}

function Test-RuleCondition {
    param(
        [string]$PropertyValue,
        [string]$Operator,
        [string]$RuleValue
    )
    # Both sides are compared case-insensitively
    switch ($Operator.ToLower()) {
        'eq'         { return $PropertyValue -ieq $RuleValue }
        'ne'         { return $PropertyValue -ine $RuleValue }
        'contains'   { return $PropertyValue -imatch [regex]::Escape($RuleValue) }
        'startswith' { return $PropertyValue.StartsWith($RuleValue, [System.StringComparison]::OrdinalIgnoreCase) }
        'endswith'   { return $PropertyValue.EndsWith($RuleValue, [System.StringComparison]::OrdinalIgnoreCase) }
        'regex'      { return $PropertyValue -imatch $RuleValue }
        default      { Write-Warning "Unknown operator '$Operator'. Treating as false."; return $false }
    }
}

function Get-MatchingPackages {
    <#
    .SYNOPSIS
        Evaluates all rule groups against one identity. Returns an array of
        @{ AccessPackageId; PolicyId } for every group whose conditions ALL match.
    #>
    param(
        [Parameter(Mandatory)]$Identity,
        [Parameter(Mandatory)][array]$RuleGroups   # grouped rules keyed by RuleGroup
    )

    $targetProps = Get-TargetProperties -Identity $Identity
    $sourceUpn   = $Identity.sourceIdentity.matchingProperty.value

    $matched = @()

    foreach ($group in $RuleGroups) {
        $allConditionsMet = $true

        foreach ($rule in $group.Rules) {
            $propName = $rule.PropertyName.Trim()
            $propValue = $null

            if ($propName -ieq 'source.userPrincipalName') {
                $propValue = $sourceUpn
            }
            elseif ($targetProps.ContainsKey($propName)) {
                # Properties are arrays; take first value
                $propValue = ($targetProps[$propName] | Select-Object -First 1)
            }

            if ($null -eq $propValue) {
                $allConditionsMet = $false
                break
            }

            if (-not (Test-RuleCondition -PropertyValue $propValue -Operator $rule.Operator -RuleValue $rule.Value)) {
                $allConditionsMet = $false
                break
            }
        }

        if ($allConditionsMet) {
            $matched += @{
                AccessPackageId = $group.AccessPackageId
                PolicyId        = $group.PolicyId
            }
        }
    }

    return $matched
}

# ---------------------------------------------------------------------------
# Validate parameters
# ---------------------------------------------------------------------------

if ($RulesFile -and -not (Test-Path $RulesFile)) {
    Write-Error "Rules file not found: $RulesFile"
    return
}

if (-not $RulesFile -and $AccessPackageId -and -not $PolicyId) {
    Write-Error "AccessPackageId was provided but PolicyId is missing. Both are required."
    return
}

if ($FallbackBehavior -eq 'UseFallback' -and (-not $AccessPackageId -or -not $PolicyId)) {
    Write-Error "FallbackBehavior is 'UseFallback' but AccessPackageId or PolicyId is missing."
    return
}

# ---------------------------------------------------------------------------
# Load rules if provided
# ---------------------------------------------------------------------------

$ruleGroups = @()

if ($RulesFile) {
    Write-Host "Loading rules from: $RulesFile" -ForegroundColor Cyan
    $csvRows = Import-Csv -Path $RulesFile

    # Validate CSV columns
    $requiredCols = @('RuleGroup', 'PropertyName', 'Operator', 'Value', 'AccessPackageId', 'PolicyId')
    $actualCols = $csvRows[0].PSObject.Properties.Name
    foreach ($col in $requiredCols) {
        if ($col -notin $actualCols) {
            Write-Error "Rules CSV is missing required column '$col'. Expected columns: $($requiredCols -join ', ')"
            return
        }
    }

    # Group rows by RuleGroup — rows in the same group are AND-ed
    $grouped = $csvRows | Group-Object -Property RuleGroup

    foreach ($g in $grouped) {
        $firstRow = $g.Group[0]
        $ruleGroups += @{
            GroupId         = $g.Name
            AccessPackageId = $firstRow.AccessPackageId.Trim()
            PolicyId        = $firstRow.PolicyId.Trim()
            Rules           = $g.Group | ForEach-Object {
                @{
                    PropertyName = $_.PropertyName
                    Operator     = $_.Operator
                    Value        = $_.Value
                }
            }
        }
    }

    Write-Host "  Loaded $($ruleGroups.Count) rule group(s) from $($csvRows.Count) row(s)." -ForegroundColor Green
    foreach ($rg in $ruleGroups) {
        $condDesc = ($rg.Rules | ForEach-Object { "$($_.PropertyName) $($_.Operator) '$($_.Value)'" }) -join ' AND '
        Write-Host "  Group $($rg.GroupId): $condDesc -> Package $($rg.AccessPackageId)" -ForegroundColor DarkCyan
    }
}

$needsEntitlementMgmt = $RulesFile -or $AccessPackageId

# ---------------------------------------------------------------------------
# Ensure Microsoft Graph connection
# ---------------------------------------------------------------------------

$requiredScopes = @(
    "AuditLog.Read.All",
    "AppRoleAssignment.ReadWrite.All",
    "Application.Read.All"
)
if ($needsEntitlementMgmt) {
    $requiredScopes += "EntitlementManagement.ReadWrite.All"
}

$context = Get-MgContext
if (-not $context) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes $requiredScopes -NoWelcome
}
else {
    Write-Host "Already connected to Microsoft Graph as $($context.Account)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 1 - Get the latest correlation report for the service principal
# ---------------------------------------------------------------------------

Write-Host "`n=== Step 1: Fetching correlation reports ===" -ForegroundColor Cyan

$correlationsUri = "https://graph.microsoft.com/beta/reports/correlations?`$filter=servicePrincipal/id eq '$ServicePrincipalId'&`$orderby=startDateTime desc&`$top=1"
$correlationsResponse = Invoke-GraphRequest -Method GET -Uri $correlationsUri

if (-not $correlationsResponse.value -or $correlationsResponse.value.Count -eq 0) {
    Write-Error "No correlation reports found for service principal '$ServicePrincipalId'."
    return
}

$latestReport = $correlationsResponse.value[0]
$correlationId = $latestReport.id

Write-Host "Latest correlation report:" -ForegroundColor Green
Write-Host "  ID:        $correlationId"
Write-Host "  Start:     $($latestReport.startDateTime)"
Write-Host "  End:       $($latestReport.endDateTime)"

# ---------------------------------------------------------------------------
# Step 2 - Show summary counts
# ---------------------------------------------------------------------------

Write-Host "`n=== Step 2: Identity summary ===" -ForegroundColor Cyan

$baseIdentitiesUri = "https://graph.microsoft.com/beta/reports/correlations/$correlationId/identities"

foreach ($status in @('uncorrelated', 'correlatedNotAssigned', 'correlatedAssigned')) {
    $countUri = "${baseIdentitiesUri}/`$count?`$filter=status eq '$status'"
    try {
        $count = Invoke-MgGraphRequest -Method GET -Uri $countUri -Headers @{ "ConsistencyLevel" = "eventual" }
        Write-Host "  ${status}: $count"
    }
    catch {
        Write-Host "  ${status}: (count unavailable)" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Step 3a - Retrieve correlatedNotAssigned identities (for enterprise app)
# ---------------------------------------------------------------------------

Write-Host "`n=== Step 3a: Retrieving correlatedNotAssigned identities ===" -ForegroundColor Cyan

$filterUri = "${baseIdentitiesUri}?`$filter=status eq 'correlatedNotAssigned'"
$rawUnassigned = Get-AllPages -Uri $filterUri

# Verify actual status — the API $filter may return extra identities
$unassignedIdentities = @($rawUnassigned | Where-Object { $_.status -eq 'correlatedNotAssigned' })
if ($rawUnassigned.Count -ne $unassignedIdentities.Count) {
    Write-Host "  Note: API returned $($rawUnassigned.Count) identities but only $($unassignedIdentities.Count) have status 'correlatedNotAssigned' (filtered client-side)." -ForegroundColor DarkYellow
}

if ($unassignedIdentities.Count -eq 0) {
    Write-Host "No correlatedNotAssigned identities found." -ForegroundColor Yellow
}
else {
    Write-Host "Found $($unassignedIdentities.Count) correlatedNotAssigned identities." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 3b - Retrieve correlatedAssigned identities (for access packages)
# ---------------------------------------------------------------------------

Write-Host "`n=== Step 3b: Retrieving correlatedAssigned identities ===" -ForegroundColor Cyan

$assignedFilterUri = "${baseIdentitiesUri}?`$filter=status eq 'correlatedAssigned'"
$rawAssigned = Get-AllPages -Uri $assignedFilterUri

# Verify actual status client-side
$assignedIdentities = @($rawAssigned | Where-Object { $_.status -eq 'correlatedAssigned' })
if ($rawAssigned.Count -ne $assignedIdentities.Count) {
    Write-Host "  Note: API returned $($rawAssigned.Count) identities but only $($assignedIdentities.Count) have status 'correlatedAssigned' (filtered client-side)." -ForegroundColor DarkYellow
}

if ($assignedIdentities.Count -eq 0) {
    Write-Host "No correlatedAssigned identities found." -ForegroundColor Yellow
}
else {
    Write-Host "Found $($assignedIdentities.Count) correlatedAssigned identities." -ForegroundColor Green
}

$allCorrelatedIdentities = @($unassignedIdentities) + @($assignedIdentities)

if ($allCorrelatedIdentities.Count -eq 0) {
    Write-Host "No correlated identities found at all. Nothing to do." -ForegroundColor Yellow
    return
}

Write-Host "Total correlated identities: $($allCorrelatedIdentities.Count) ($($unassignedIdentities.Count) unassigned + $($assignedIdentities.Count) assigned)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 4 - Assign users to the enterprise application
# ---------------------------------------------------------------------------

Write-Host "`n=== Step 4: Assigning correlatedNotAssigned users to enterprise app ===" -ForegroundColor Cyan

if ($SkipAppRoleAssignment) {
    Write-Host "Skipping enterprise app assignment (-SkipAppRoleAssignment specified)." -ForegroundColor DarkGray
    $assignedCount = 0
    $failedCount = 0
}
elseif ($unassignedIdentities.Count -eq 0) {
    Write-Host "No correlatedNotAssigned users to assign. Skipping." -ForegroundColor DarkGray
    $assignedCount = 0
    $failedCount = 0
}
else {

$appRoleUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId/appRoleAssignedTo"
$assignedCount = 0
$failedCount = 0

foreach ($identity in $unassignedIdentities) {
    $userId      = Get-IdentityUserId -Identity $identity
    $displayName = Get-IdentityDisplayName -Identity $identity

    if (-not $userId) {
        Write-Warning "Skipping identity with no resolvable user ID: $($identity | ConvertTo-Json -Depth 3 -Compress)"
        Add-ResultEntry -UserId '' -DisplayName '' -Status $identity.status -Step 'AppRole' -Action 'Failed' -Details 'No resolvable user ID'
        $failedCount++
        continue
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would assign user '$displayName' ($userId) to app role." -ForegroundColor Yellow
        Add-ResultEntry -UserId $userId -DisplayName $displayName -Status $identity.status -Step 'AppRole' -Action 'DryRun' -Details "AppRoleId=$AppRoleId"
        $assignedCount++
        continue
    }

    $body = @{
        principalId = $userId
        resourceId  = $ServicePrincipalId
        appRoleId   = $AppRoleId
    }

    try {
        Invoke-GraphRequest -Method POST -Uri $appRoleUri -Body $body | Out-Null
        Write-Host "  Assigned '$displayName' ($userId) to enterprise app." -ForegroundColor Green
        Add-ResultEntry -UserId $userId -DisplayName $displayName -Status $identity.status -Step 'AppRole' -Action 'Assigned' -Details "AppRoleId=$AppRoleId"
        $assignedCount++
    }
    catch {
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "Permission being assigned already exists") {
            Write-Host "  Skipped '$displayName' ($userId) - already assigned." -ForegroundColor DarkGray
            Add-ResultEntry -UserId $userId -DisplayName $displayName -Status $identity.status -Step 'AppRole' -Action 'AlreadyAssigned'
            $assignedCount++
        }
        else {
            Write-Warning "  Failed to assign '$displayName' ($userId): $errorMsg"
            Add-ResultEntry -UserId $userId -DisplayName $displayName -Status $identity.status -Step 'AppRole' -Action 'Failed' -Details $errorMsg
            $failedCount++
        }
    }
}

} # end else (not skipped)

Write-Host "`nEnterprise app assignment complete: $assignedCount succeeded, $failedCount failed." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Step 5 - Assign users to access packages
# ---------------------------------------------------------------------------

if (-not $RulesFile -and -not $AccessPackageId) {
    Write-Host "`nNo access package assignment requested. Skipping step 5." -ForegroundColor DarkGray
    Write-Host "`nAll done." -ForegroundColor Green
    return
}

Write-Host "`n=== Step 5: Assigning all correlated users to access packages ===" -ForegroundColor Cyan
Write-Host "Processing $($allCorrelatedIdentities.Count) correlated identities for access package routing..." -ForegroundColor Cyan

$assignmentRequestUri = "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentRequests"
$pkgAssignedCount = 0
$pkgSkippedCount = 0
$pkgFailedCount = 0

foreach ($identity in $allCorrelatedIdentities) {
    $userId      = Get-IdentityUserId -Identity $identity
    $displayName = Get-IdentityDisplayName -Identity $identity

    if (-not $userId) {
        Add-ResultEntry -UserId '' -DisplayName '' -Status $identity.status -Step 'AccessPackage' -Action 'Failed' -Details 'No resolvable user ID'
        $pkgFailedCount++
        continue
    }

    # Determine which packages this user should be assigned to
    $packages = @()

    if ($RulesFile) {
        $packages = @(Get-MatchingPackages -Identity $identity -RuleGroups $ruleGroups)

        if ($packages.Count -eq 0) {
            if ($FallbackBehavior -eq 'UseFallback' -and $AccessPackageId -and $PolicyId) {
                $packages = @(@{ AccessPackageId = $AccessPackageId; PolicyId = $PolicyId })
                Write-Host "  No rule matched '$displayName' - using fallback package." -ForegroundColor DarkYellow
            }
            else {
                Write-Host "  No rule matched '$displayName' ($userId) - skipping." -ForegroundColor DarkGray
                Add-ResultEntry -UserId $userId -DisplayName $displayName -Status $identity.status -Step 'AccessPackage' -Action 'NoRuleMatch'
                $pkgSkippedCount++
                continue
            }
        }
        else {
            $pkgIds = ($packages | ForEach-Object { $_.AccessPackageId }) -join ', '
            Write-Host "  '$displayName' matched $($packages.Count) rule(s) -> packages: $pkgIds" -ForegroundColor DarkCyan
        }
    }
    else {
        # Simple mode - single package for everyone
        $packages = @(@{ AccessPackageId = $AccessPackageId; PolicyId = $PolicyId })
    }

    foreach ($pkg in $packages) {
        # Pre-check: skip if user already has an active assignment for this package
        $existingUri = "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignments?`$filter=target/objectId eq '$userId' and accessPackage/id eq '$($pkg.AccessPackageId)'&`$select=id,state"
        try {
            $existing = Invoke-GraphRequest -Method GET -Uri $existingUri
            $activeAssignment = $existing.value | Where-Object { $_.state -eq 'delivered' -or $_.state -eq 'delivering' }
            if ($activeAssignment) {
                Write-Host "  Skipped '$displayName' ($userId) - already assigned to package $($pkg.AccessPackageId)." -ForegroundColor DarkGray
                Add-ResultEntry -UserId $userId -DisplayName $displayName -Status $identity.status -Step 'AccessPackage' -Action 'AlreadyAssigned' -AccessPackageId $pkg.AccessPackageId -PolicyId $pkg.PolicyId
                $pkgSkippedCount++
                continue
            }
        }
        catch {
            # If the check fails, proceed with the assignment attempt
            Write-Host "  Could not verify existing assignment for '$displayName' - proceeding." -ForegroundColor DarkYellow
        }

        if ($DryRun) {
            Write-Host "  [DRY RUN] Would assign '$displayName' ($userId) to package $($pkg.AccessPackageId) with policy $($pkg.PolicyId)." -ForegroundColor Yellow
            Add-ResultEntry -UserId $userId -DisplayName $displayName -Status $identity.status -Step 'AccessPackage' -Action 'DryRun' -AccessPackageId $pkg.AccessPackageId -PolicyId $pkg.PolicyId
            $pkgAssignedCount++
            continue
        }

        $body = @{
            requestType = "adminAdd"
            assignment  = @{
                targetId           = $userId
                assignmentPolicyId = $pkg.PolicyId
                accessPackageId    = $pkg.AccessPackageId
            }
        }

        try {
            Invoke-GraphRequest -Method POST -Uri $assignmentRequestUri -Body $body | Out-Null
            Write-Host "  Assigned '$displayName' ($userId) to package $($pkg.AccessPackageId)." -ForegroundColor Green
            Add-ResultEntry -UserId $userId -DisplayName $displayName -Status $identity.status -Step 'AccessPackage' -Action 'Assigned' -AccessPackageId $pkg.AccessPackageId -PolicyId $pkg.PolicyId
            $pkgAssignedCount++
        }
        catch {
            Write-Warning "  Failed package request for '$displayName' ($userId) pkg=$($pkg.AccessPackageId): $($_.Exception.Message)"
            Add-ResultEntry -UserId $userId -DisplayName $displayName -Status $identity.status -Step 'AccessPackage' -Action 'Failed' -AccessPackageId $pkg.AccessPackageId -PolicyId $pkg.PolicyId -Details $_.Exception.Message
            $pkgFailedCount++
        }
    }
}

Write-Host "`nAccess package results: $pkgAssignedCount assigned, $pkgSkippedCount skipped (no match or already assigned), $pkgFailedCount failed." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Export results
# ---------------------------------------------------------------------------

if ($OutputFile) {
    $resultsLog | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
    Write-Host "`nResults exported to: $OutputFile ($($resultsLog.Count) entries)" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

Write-Host "`nAll done." -ForegroundColor Green
