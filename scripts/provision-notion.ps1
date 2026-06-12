# provision-notion.ps1
#
# Provision the "AI Sherpa - Development & Activity" workspace in Notion:
# parent page + Roadmap database + 5 properties + 5 roadmap items (each with
# description paragraph + checklist of to-do blocks).
#
# Secret hygiene:
#   - Token is read from $env:NOTION_TOKEN. NEVER pass it as a parameter,
#     never hardcode, never commit.
#   - Rotate the integration secret in Notion after running if it was ever
#     exposed (chat, screen share, log file).
#
# Notion API limitations to know:
#   - The API cannot create or configure database VIEWS. After this script
#     runs, you must add the 5 views (Board / By Category / Table / Active /
#     This week) manually in the UI (~2 min).
#   - The 'status' property type cannot be fully configured via API. We use
#     a 'select' property for Status with the 5 desired options instead;
#     you can convert it to a true Status type in the UI later if you want
#     the To-do / In progress / Complete groupings.
#
# Usage:
#   $env:NOTION_TOKEN = "ntn_..."
#   .\scripts\provision-notion.ps1 -ParentPageId "3784272f9aa180b3bab4fbe3c1d8f1c7"
#
#   # Re-running is safe - the script skips items that already exist by title.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ParentPageId,

    [string]$PageTitle = 'AI Sherpa - Development & Activity',
    [string]$DatabaseTitle = 'Roadmap'
)

$ErrorActionPreference = 'Stop'
$NotionApi = 'https://api.notion.com/v1'
$NotionVersion = '2022-06-28'

# ---------------------------------------------------------------------------
# Token + auth headers
# ---------------------------------------------------------------------------
if (-not $env:NOTION_TOKEN) {
    Write-Error @'
NOTION_TOKEN env var is not set. Set it in this PowerShell session first:

    $env:NOTION_TOKEN = "ntn_..."

Then re-run this script. The token is read from the env var so it never
appears in command transcripts or script files.
'@
    exit 1
}

$headers = @{
    Authorization    = "Bearer $($env:NOTION_TOKEN)"
    'Notion-Version' = $NotionVersion
    'Content-Type'   = 'application/json'
}

function Invoke-Notion {
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,
        [object]$Body
    )
    $uri = "$NotionApi$Path"
    $params = @{
        Uri     = $uri
        Method  = $Method
        Headers = $headers
    }
    if ($Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }
    try {
        return Invoke-RestMethod @params
    } catch {
        $respBody = ''
        if ($_.ErrorDetails) { $respBody = $_.ErrorDetails.Message }
        throw "Notion API $Method $Path failed: $($_.Exception.Message)`nBody: $respBody"
    }
}

# ---------------------------------------------------------------------------
# 0. Validate token
# ---------------------------------------------------------------------------
Write-Host 'Validating integration token...'
$me = Invoke-Notion -Method GET -Path '/users/me'
Write-Host "  OK - bot: $($me.name) (id: $($me.id))"

# ---------------------------------------------------------------------------
# 1. Create (or reuse) the workspace page under ParentPageId
# ---------------------------------------------------------------------------
Write-Host "Looking for existing page '$PageTitle' under parent $ParentPageId..."
$existingPage = $null
$cursor = $null
do {
    $path = "/blocks/$ParentPageId/children?page_size=100"
    if ($cursor) { $path += "&start_cursor=$cursor" }
    $resp = Invoke-Notion -Method GET -Path $path
    foreach ($child in $resp.results) {
        if ($child.type -eq 'child_page' -and $child.child_page.title -eq $PageTitle) {
            $existingPage = $child
            break
        }
    }
    $cursor = $resp.next_cursor
} while ($cursor -and -not $existingPage)

if ($existingPage) {
    $workspacePageId = $existingPage.id
    Write-Host "  Reusing existing page: $workspacePageId"
} else {
    if ($PSCmdlet.ShouldProcess($PageTitle, 'Create page')) {
        $body = @{
            parent     = @{ page_id = $ParentPageId }
            properties = @{
                title = @(
                    @{ type = 'text'; text = @{ content = $PageTitle } }
                )
            }
        }
        $page = Invoke-Notion -Method POST -Path '/pages' -Body $body
        $workspacePageId = $page.id
        Write-Host "  Created page: $workspacePageId"
    } else {
        $workspacePageId = '<dry-run-page-id>'
    }
}

# ---------------------------------------------------------------------------
# 2. Create (or reuse) the Roadmap database under the workspace page
# ---------------------------------------------------------------------------
Write-Host "Looking for existing database '$DatabaseTitle' under workspace page..."
$existingDb = $null
$cursor = $null
do {
    $path = "/blocks/$workspacePageId/children?page_size=100"
    if ($cursor) { $path += "&start_cursor=$cursor" }
    $resp = Invoke-Notion -Method GET -Path $path
    foreach ($child in $resp.results) {
        if ($child.type -eq 'child_database' -and $child.child_database.title -eq $DatabaseTitle) {
            $existingDb = $child
            break
        }
    }
    $cursor = $resp.next_cursor
} while ($cursor -and -not $existingDb)

if ($existingDb) {
    $databaseId = $existingDb.id
    Write-Host "  Reusing existing database: $databaseId"
} else {
    if ($PSCmdlet.ShouldProcess($DatabaseTitle, 'Create database')) {
        $dbBody = @{
            parent     = @{ type = 'page_id'; page_id = $workspacePageId }
            title      = @(
                @{ type = 'text'; text = @{ content = $DatabaseTitle } }
            )
            properties = [ordered]@{
                'Name'           = @{ title = @{} }
                'Status'         = @{
                    select = @{
                        options = @(
                            @{ name = 'Backlog';             color = 'gray'   },
                            @{ name = 'Next up';             color = 'blue'   },
                            @{ name = 'In progress';         color = 'yellow' },
                            @{ name = 'In review / testing'; color = 'orange' },
                            @{ name = 'Done';                color = 'green'  }
                        )
                    }
                }
                'Category'       = @{
                    select = @{
                        options = @(
                            @{ name = 'Feedback loop';      color = 'blue'   },
                            @{ name = 'Knowledge';          color = 'green'  },
                            @{ name = 'Release automation'; color = 'yellow' },
                            @{ name = 'Distribution / IT';  color = 'purple' },
                            @{ name = 'Repo structure';     color = 'orange' }
                        )
                    }
                }
                'Priority'       = @{
                    select = @{
                        options = @(
                            @{ name = 'High';   color = 'red'    },
                            @{ name = 'Medium'; color = 'yellow' },
                            @{ name = 'Low';    color = 'gray'   }
                        )
                    }
                }
                'Owner'          = @{ people = @{} }
                'Target release' = @{ rich_text = @{} }
                'Spec / PR'      = @{ url = @{} }
            }
        }
        $db = Invoke-Notion -Method POST -Path '/databases' -Body $dbBody
        $databaseId = $db.id
        Write-Host "  Created database: $databaseId"
    } else {
        $databaseId = '<dry-run-db-id>'
    }
}

# ---------------------------------------------------------------------------
# 3. Define the 5 roadmap items
# ---------------------------------------------------------------------------
$items = @(
    @{
        title       = 'Lesson-learn feedback loop and dashboard'
        category    = 'Feedback loop'
        priority    = 'Medium'
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
        category    = 'Knowledge'
        priority    = 'Medium'
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
        category    = 'Release automation'
        priority    = 'Medium'
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
        category    = 'Distribution / IT'
        priority    = 'Medium'
        description = 'Distribute weekly updates through IT-managed channels so developer machines stay current without manual setup.'
        checklist   = @(
            'Talk to IT (Intune? winget?)',
            'Packaging format',
            'Update channel design',
            'Signed installer',
            'Pilot on 3 machines',
            'Org rollout'
        )
    },
    @{
        title       = 'Restructure repo to Universal Repository Framework'
        category    = 'Repo structure'
        priority    = 'High'
        description = "Align AI Sherpa repo layout with Shyam's Universal Repository Framework: root limited to project-wide files; canonical subfolders for specs / src / tests / docs / knowledge / prompts / data / scripts / assets / archive / scratchpad / .claude. Each top-level dir documents Purpose / Why / Memory Aid. Resolve AI-Sherpa-specific deviations (core/, domains/, setup.ps1 at root) before migrating."
        checklist   = @(
            'Gap analysis: map current dirs/files to framework targets',
            "Decide AI-Sherpa-specific deviations (core/, domains/, setup at root) - get Shyam's sign-off",
            'Migration plan: file moves + path/import updates + setup.ps1 / setup.sh path updates',
            'Move project-wide files to root, everything else into subfolders',
            'Add README.md in each new top-level dir with Purpose / Why / Memory Aid',
            'Update CLAUDE.md, README.md, ROADMAP.md references to new paths',
            'Run full setup smoke test on Win + WSL',
            'CHANGELOG entry + breaking-change note for users'
        )
    }
)

# ---------------------------------------------------------------------------
# 4. Look up existing items in the database so we can skip duplicates
# ---------------------------------------------------------------------------
$existingTitles = @{}
if ($databaseId -ne '<dry-run-db-id>') {
    $cursor = $null
    do {
        $body = @{ page_size = 100 }
        if ($cursor) { $body['start_cursor'] = $cursor }
        $resp = Invoke-Notion -Method POST -Path "/databases/$databaseId/query" -Body $body
        foreach ($p in $resp.results) {
            $titleProp = $p.properties.Name.title
            if ($titleProp -and $titleProp.Count -gt 0) {
                $existingTitles[$titleProp[0].plain_text] = $p.id
            }
        }
        $cursor = $resp.next_cursor
    } while ($cursor)
}

# ---------------------------------------------------------------------------
# 5. Create items (idempotent by title)
# ---------------------------------------------------------------------------
foreach ($item in $items) {
    if ($existingTitles.ContainsKey($item.title)) {
        Write-Host "Item exists - skipping: $($item.title)"
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($item.title, 'Create item')) { continue }

    # 5a. Create the page with properties
    $pageBody = @{
        parent     = @{ database_id = $databaseId }
        properties = @{
            'Name'     = @{ title = @( @{ text = @{ content = $item.title } } ) }
            'Status'   = @{ select = @{ name = 'Backlog' } }
            'Category' = @{ select = @{ name = $item.category } }
            'Priority' = @{ select = @{ name = $item.priority } }
        }
    }
    $newPage = Invoke-Notion -Method POST -Path '/pages' -Body $pageBody
    Write-Host "Created item: $($item.title)"

    # 5b. Append description paragraph + checklist to-do blocks
    $children = @(
        @{
            object    = 'block'
            type      = 'paragraph'
            paragraph = @{
                rich_text = @( @{ type = 'text'; text = @{ content = $item.description } } )
            }
        }
    )
    foreach ($cl in $item.checklist) {
        $children += @{
            object = 'block'
            type   = 'to_do'
            to_do  = @{
                rich_text = @( @{ type = 'text'; text = @{ content = $cl } } )
                checked   = $false
            }
        }
    }
    $blocksBody = @{ children = $children }
    Invoke-Notion -Method PATCH -Path "/blocks/$($newPage.id)/children" -Body $blocksBody | Out-Null
    Write-Host "  - description + $($item.checklist.Count) checklist items"
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
$pageUrl = "https://www.notion.so/$($workspacePageId -replace '-','')"
$dbUrl   = "https://www.notion.so/$($databaseId -replace '-','')"

Write-Host ''
Write-Host '[OK] Provisioning complete.'
Write-Host "  Workspace page : $pageUrl"
Write-Host "  Roadmap DB     : $dbUrl"
Write-Host ''
Write-Host 'Next (manual, ~2 min):'
Write-Host '  Open the Roadmap database -> + Add view -> add the 5 views from'
Write-Host '  docs/notion-blueprint.md section 3.'
