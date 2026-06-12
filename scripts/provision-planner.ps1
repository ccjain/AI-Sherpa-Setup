# provision-planner.ps1
#
# Provision the "AI Sherpa - Roadmap" Microsoft Planner plan: 5 status buckets,
# 4 category labels, 4 roadmap tasks (each with description + checklist).
#
# Auth: Microsoft Graph PowerShell SDK (delegated, device-code or interactive).
#       No app registration required - uses Microsoft's public client app.
#       The signed-in user must be a MEMBER of the target M365 group.
#
# REQUIRES TENANT POLICY: delegated scopes Group.ReadWrite.All and
# Tasks.ReadWrite must be consentable by end users. Many enterprise tenants
# (including the AI Sherpa default) lock these behind admin consent and IT
# will not grant them on request. If Connect-MgGraph fails with a consent
# error, fall back to the manual setup in docs/planner-blueprint.md.
#
# Idempotent: re-running skips items that already exist by title/name.
#
# Usage:
#   pwsh scripts/provision-planner.ps1 -GroupName "AI Sherpa Team"
#   pwsh scripts/provision-planner.ps1 -GroupId "<guid>" -PlanName "AI Sherpa - Roadmap"
#   pwsh scripts/provision-planner.ps1 -WhatIf       # dry run, no writes

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$PlanName = 'AI Sherpa - Roadmap',
    [string]$GroupName,
    [string]$GroupId,
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'
$GraphBase = 'https://graph.microsoft.com/v1.0'

# ---------------------------------------------------------------------------
# 1. Ensure Microsoft.Graph.Authentication module
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Host '[ACTION REQUIRED] Installing Microsoft.Graph.Authentication for current user...'
    if ($PSCmdlet.ShouldProcess('Microsoft.Graph.Authentication', 'Install-Module')) {
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
    }
}
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

# ---------------------------------------------------------------------------
# 2. Connect with required delegated scopes
# ---------------------------------------------------------------------------
$scopes = @(
    'Group.ReadWrite.All',
    'Tasks.ReadWrite',
    'GroupMember.Read.All',
    'User.Read'
)

$ctx = Get-MgContext
if (-not $ctx -or ($scopes | Where-Object { $_ -notin $ctx.Scopes })) {
    Write-Host "Connecting to Microsoft Graph with scopes: $($scopes -join ', ')"
    if ($PSCmdlet.ShouldProcess('Microsoft Graph', 'Connect-MgGraph')) {
        if ($UseDeviceCode) {
            Write-Host '[ACTION REQUIRED] Follow the device-code prompt below in any browser:'
            Connect-MgGraph -Scopes $scopes -NoWelcome -UseDeviceCode
        } else {
            Connect-MgGraph -Scopes $scopes -NoWelcome
        }
    }
}

# ---------------------------------------------------------------------------
# 3. Resolve the M365 group that will own the plan
# ---------------------------------------------------------------------------
if (-not $GroupId) {
    if (-not $GroupName) {
        Write-Host ''
        Write-Host 'Groups you are a member of:'
        $myGroups = Invoke-MgGraphRequest -Method GET `
            -Uri "$GraphBase/me/memberOf?`$select=id,displayName&`$top=100"
        $i = 0
        $candidates = @($myGroups.value | Where-Object { $_['@odata.type'] -eq '#microsoft.graph.group' })
        foreach ($g in $candidates) {
            Write-Host ("  [{0}] {1}" -f $i, $g.displayName)
            $i++
        }
        if ($candidates.Count -eq 0) {
            throw 'You are not a member of any M365 groups. Create or join one first.'
        }
        $pick = Read-Host 'Pick a group number'
        $GroupId = $candidates[[int]$pick].id
        $GroupName = $candidates[[int]$pick].displayName
    } else {
        $escaped = $GroupName.Replace("'", "''")
        $resp = Invoke-MgGraphRequest -Method GET `
            -Uri "$GraphBase/groups?`$filter=displayName eq '$escaped'"
        if (-not $resp.value -or $resp.value.Count -eq 0) {
            throw "Group not found by display name: '$GroupName'"
        }
        $GroupId = $resp.value[0].id
    }
}
Write-Host "Using group: $GroupName ($GroupId)"

# ---------------------------------------------------------------------------
# 4. Create (or reuse) the plan
# ---------------------------------------------------------------------------
$existingPlans = Invoke-MgGraphRequest -Method GET `
    -Uri "$GraphBase/groups/$GroupId/planner/plans"
$plan = $existingPlans.value | Where-Object { $_.title -eq $PlanName } | Select-Object -First 1

if ($plan) {
    $planId = $plan.id
    Write-Host "Plan exists: '$PlanName' ($planId) - syncing structure"
} else {
    if ($PSCmdlet.ShouldProcess($PlanName, 'Create Planner plan')) {
        $body = @{ owner = $GroupId; title = $PlanName } | ConvertTo-Json
        $plan = Invoke-MgGraphRequest -Method POST -Uri "$GraphBase/planner/plans" `
            -Body $body -ContentType 'application/json'
        $planId = $plan.id
        Write-Host "Created plan: '$PlanName' ($planId)"
    } else {
        $planId = '<dry-run-plan-id>'
    }
}

# ---------------------------------------------------------------------------
# 5. Set category labels (categoryDescriptions on plan details)
#    Planner labels are category1..category25; we use the first 4.
# ---------------------------------------------------------------------------
$labels = [ordered]@{
    category1 = 'Feedback loop'
    category2 = 'Knowledge'
    category3 = 'Release automation'
    category4 = 'Distribution / IT'
}

if ($planId -ne '<dry-run-plan-id>') {
    $details = Invoke-MgGraphRequest -Method GET `
        -Uri "$GraphBase/planner/plans/$planId/details"
    $etag = $details['@odata.etag']
    $body = @{ categoryDescriptions = $labels } | ConvertTo-Json
    if ($PSCmdlet.ShouldProcess('plan details', 'PATCH categoryDescriptions')) {
        Invoke-MgGraphRequest -Method PATCH `
            -Uri "$GraphBase/planner/plans/$planId/details" `
            -Body $body -ContentType 'application/json' `
            -Headers @{ 'If-Match' = $etag } | Out-Null
        Write-Host 'Labels set: Feedback loop / Knowledge / Release automation / Distribution / IT'
    }
}

# ---------------------------------------------------------------------------
# 6. Buckets (in display order; orderHint " !" appends to end)
# ---------------------------------------------------------------------------
$bucketNames = @('Backlog', 'Next up', 'In progress', 'In review / testing', 'Done')
$bucketIds = @{}

$existingBuckets = if ($planId -ne '<dry-run-plan-id>') {
    (Invoke-MgGraphRequest -Method GET -Uri "$GraphBase/planner/plans/$planId/buckets").value
} else { @() }

foreach ($name in $bucketNames) {
    $existing = $existingBuckets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($existing) {
        $bucketIds[$name] = $existing.id
        Write-Host "Bucket exists: $name"
        continue
    }
    if ($PSCmdlet.ShouldProcess($name, 'Create bucket')) {
        $body = @{
            name      = $name
            planId    = $planId
            orderHint = ' !'
        } | ConvertTo-Json
        $created = Invoke-MgGraphRequest -Method POST -Uri "$GraphBase/planner/buckets" `
            -Body $body -ContentType 'application/json'
        $bucketIds[$name] = $created.id
        Write-Host "Created bucket: $name"
    } else {
        $bucketIds[$name] = "<dry-run-bucket-$name>"
    }
}

# ---------------------------------------------------------------------------
# 7. Tasks - all start in Backlog, each tagged with its category label
# ---------------------------------------------------------------------------
$tasks = @(
    @{
        title       = 'Lesson-learn feedback loop and dashboard'
        category    = 'category1'
        description = 'Capture per-session learnings from developers and surface them in a team-visible dashboard.'
        checklist   = @(
            'Decide capture mechanism (daemon vs. opt-in cmd)',
            'Pick storage backend (OneDrive / Git / DB)',
            'Dashboard spec',
            'MVP dashboard',
            'Pilot with 2 devs',
            'Team rollout'
        )
    },
    @{
        title       = 'Toolchain-specific lesson-learn knowledge'
        category    = 'category2'
        description = 'Separate lesson stores per toolchain (embedded / web / AI) so insights flow to the right audience.'
        checklist   = @(
            'Define toolchain taxonomy (embedded / web / AI)',
            'Tagging at capture time',
            'Per-toolchain retrieval slice',
            'Index into Claude memory',
            'Validate routing'
        )
    },
    @{
        title       = 'Weekly release automation + auto-test'
        category    = 'category3'
        description = 'Auto-notify the team on new releases and run the release through an automated test pass before announcement.'
        checklist   = @(
            'Pick CI surface (GitHub Actions)',
            'Smoke-test matrix (Win / WSL)',
            'Release notes generator',
            'Teams / email notification',
            'Cut first automated release'
        )
    },
    @{
        title       = 'IT-managed auto-install and weekly update'
        category    = 'category4'
        description = 'Distribute weekly updates through IT-managed channels so developer machines stay current without manual setup.'
        checklist   = @(
            'Talk to IT (Intune? winget?)',
            'Packaging format',
            'Update channel design',
            'Signed installer',
            'Pilot on 3 machines',
            'Org rollout'
        )
    }
)

$existingTasks = if ($planId -ne '<dry-run-plan-id>') {
    (Invoke-MgGraphRequest -Method GET -Uri "$GraphBase/planner/plans/$planId/tasks").value
} else { @() }

foreach ($t in $tasks) {
    $existing = $existingTasks | Where-Object { $_.title -eq $t.title } | Select-Object -First 1
    if ($existing) {
        Write-Host "Task exists: $($t.title) - skipping"
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($t.title, 'Create task + details')) { continue }

    # 7a. Create task
    $taskBody = @{
        planId            = $planId
        bucketId          = $bucketIds['Backlog']
        title             = $t.title
        appliedCategories = @{ ($t.category) = $true }
    } | ConvertTo-Json -Depth 4
    $created = Invoke-MgGraphRequest -Method POST -Uri "$GraphBase/planner/tasks" `
        -Body $taskBody -ContentType 'application/json'
    Write-Host "Created task: $($t.title) ($($created.id))"

    # 7b. PATCH task details with description + checklist
    #     Planner sometimes 404s the details endpoint immediately after create;
    #     retry briefly until it's available.
    $taskId = $created.id
    $details = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $details = Invoke-MgGraphRequest -Method GET `
                -Uri "$GraphBase/planner/tasks/$taskId/details"
            break
        } catch {
            Start-Sleep -Milliseconds (500 * $attempt)
        }
    }
    if (-not $details) {
        Write-Warning "Could not fetch details for task $taskId - skipping description/checklist."
        continue
    }
    $etag = $details['@odata.etag']

    $checklist = @{}
    foreach ($item in $t.checklist) {
        $guid = [guid]::NewGuid().ToString()
        $checklist[$guid] = @{
            '@odata.type' = '#microsoft.graph.plannerChecklistItem'
            title         = $item
            isChecked     = $false
        }
    }
    $detailsBody = @{
        description = $t.description
        checklist   = $checklist
    } | ConvertTo-Json -Depth 6

    Invoke-MgGraphRequest -Method PATCH `
        -Uri "$GraphBase/planner/tasks/$taskId/details" `
        -Body $detailsBody -ContentType 'application/json' `
        -Headers @{ 'If-Match' = $etag } | Out-Null
    Write-Host "  - description + $($t.checklist.Count) checklist items set"
}

Write-Host ''
Write-Host "[OK] Plan provisioned: '$PlanName'"
Write-Host "      Open in Teams -> 'Tasks by Planner and To Do' -> '$PlanName'"
Write-Host "      Or web: https://tasks.office.com/"
