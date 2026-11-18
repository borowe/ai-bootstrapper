# Scaffolds a planner/coder/reviewer workflow with per-task artifacts.
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File .\scaffold-agents.ps1 [-Claude] [-Force] [-Root .]
param(
    [string]$Root = ".",
    [switch]$Claude,   # also generate .claude/agents/ (Claude Code format)
    [switch]$Force     # overwrite existing files
)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path $Root).Path
$utf8 = New-Object System.Text.UTF8Encoding $false

function W($rel, $content) {
    $full = Join-Path $Root $rel
    if ((Test-Path $full) -and -not $Force) { Write-Host "skip   $rel"; return }
    $dir = Split-Path $full
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($full, $content, $utf8)
    Write-Host "create $rel"
}

# ------------------------------------------------------------ repo-wide docs
W "AGENTS.md" @'
# Agent conventions

## Workflow
Every coding task runs through three roles, handing off via files in `tasks/<task>/`:

1. **Planner** reads `00-brief.md`, writes `01-plan.md`. Never edits source.
2. **Coder** reads the plan, implements it, writes `02-implementation.md`.
3. **Reviewer** reads everything plus the diff, writes `03-review.md`. Never fixes code.

The active task folder name is in `tasks/ACTIVE`. Create a task with:
`.\scripts\new-task.ps1 "Short task title"`

Files are the handoff. Do not rely on chat history; re-read the artifacts.

## Project conventions
<!-- Fill in. Agents read this file. -->
- Language / framework:
- Install:
- Test command:
- Lint / format command:
- Type check command:
- Code style notes:
'@

W ".github/copilot-instructions.md" @'
Follow `AGENTS.md` for workflow and project conventions.
Task artifacts live in `tasks/<task>/`; the active task is named in `tasks/ACTIVE`.
'@

# ------------------------------------------------------------ task templates
W "tasks/_template/00-brief.md" @'
# {{TITLE}}

## Goal
<!-- One or two sentences. What should be true when this is done? -->

## Context
<!-- Relevant files, prior decisions, links. -->

## Constraints
<!-- Performance, compatibility, dependencies, style. -->

## Acceptance criteria
- [ ]
- [ ]

## Out of scope
-
'@

W "tasks/_template/01-plan.md" @'
---
status: draft   # draft | ready
---
# Plan

## Goal
## Files to touch
| File | Change |
| --- | --- |

## Steps
1.
2.

## Risks
## Test plan
## Open questions
<!-- Must be empty (or resolved by the user) before status: ready -->
'@

W "tasks/_template/02-implementation.md" @'
# Implementation

## Steps completed
<!-- Reference plan step numbers. -->

## Deviations from plan
<!-- Every departure, with the reason. "None" if none. -->

## Files changed
## Commands run
## Test results
## Known gaps
'@

W "tasks/_template/03-review.md" @'
---
status: pending   # pending | approved | changes_requested
---
# Review

## Summary
## Plan conformance
<!-- Does the implementation match 01-plan.md and the brief's acceptance criteria? -->

## Findings
| Severity (blocker/major/minor) | Location (file:line) | Issue | Suggested fix |
| --- | --- | --- | --- |

## Tests
<!-- What was run, what passed, what is missing. -->
'@

# ------------------------------------------------------------ new-task helper
W "scripts/new-task.ps1" @'
param([Parameter(Mandatory)][string]$Title)
$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding $false
$root = Split-Path $PSScriptRoot
$slug = ($Title.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
$name = "$(Get-Date -Format 'yyyy-MM-dd')-$slug"
$dest = Join-Path $root "tasks/$name"
if (Test-Path $dest) { throw "Task already exists: $name" }

Copy-Item (Join-Path $root "tasks/_template") $dest -Recurse
$brief = Join-Path $dest "00-brief.md"
$text = [System.IO.File]::ReadAllText($brief).Replace('{{TITLE}}', $Title)
[System.IO.File]::WriteAllText($brief, $text, $utf8)
[System.IO.File]::WriteAllText((Join-Path $root "tasks/ACTIVE"), $name, $utf8)

Write-Host "Created tasks/$name (now active)"
Write-Host "Next: fill in 00-brief.md, then switch to the Planner agent."
'@

W ".github/prompts/new-task.prompt.md" @'
---
description: Create a new task folder and make it active
agent: agent
tools: ['execute']
---
Run `.\scripts\new-task.ps1 "${input:title:Short task title}"` in the terminal,
then report the created folder name. Do nothing else.
'@

# ------------------------------------------------------------ agent definitions
$roles = @(
    @{
        Name = "Planner"; File = "planner"
        Desc = "Produces an implementation plan from the task brief. Never edits source code."
        VsTools = "['read', 'search', 'web', 'edit']"
        ClaudeTools = "Read, Grep, Glob, Write"; ClaudeModel = "opus"
        Handoffs = @'
handoffs:
  - label: Implement plan
    agent: Coder
    prompt: Implement the plan in the active task folder (see tasks/ACTIVE).
    send: false
'@
        Body = @'
You are the planner. You never modify source code.

1. Read `tasks/ACTIVE` for the active folder name, then `tasks/<name>/00-brief.md` and `AGENTS.md`.
2. Explore the codebase to understand the affected areas.
3. Write `tasks/<name>/01-plan.md` using the structure in `tasks/_template/01-plan.md`.
4. List concrete files, ordered steps, risks, and a test plan.
5. Put unresolved questions under "Open questions" and ask the user. Set `status: ready` only when none remain.

The only file you may create or modify is `01-plan.md`.
'@
    },
    @{
        Name = "Coder"; File = "coder"
        Desc = "Implements the approved plan and records what changed."
        VsTools = "['read', 'search', 'edit', 'execute']"
        ClaudeTools = "Read, Grep, Glob, Edit, Write, Bash"; ClaudeModel = "sonnet"
        Handoffs = @'
handoffs:
  - label: Review implementation
    agent: Reviewer
    prompt: Review the implementation for the active task (see tasks/ACTIVE).
    send: false
'@
        Body = @'
You are the coder.

1. Read `tasks/ACTIVE`, then `01-plan.md` and `AGENTS.md`. If the plan is not `status: ready`, stop and say so.
2. Implement the steps in order. Do not expand scope beyond the plan.
3. Run the test, lint, and type-check commands from `AGENTS.md`. Fix failures you caused.
4. Write `02-implementation.md` using `tasks/_template/02-implementation.md`.
   Log every deviation from the plan with the reason.

If `03-review.md` exists with `status: changes_requested`: address each finding,
then append a `## Round N` section to `02-implementation.md` describing the fixes.

Never edit `00-brief.md`, `01-plan.md`, or `03-review.md`.
'@
    },
    @{
        Name = "Reviewer"; File = "reviewer"
        Desc = "Reviews the implementation against the plan and brief. Reports findings, never fixes code."
        VsTools = "['read', 'search', 'edit', 'execute']"
        ClaudeTools = "Read, Grep, Glob, Bash, Write"; ClaudeModel = "sonnet"
        Handoffs = @'
handoffs:
  - label: Send findings to coder
    agent: Coder
    prompt: Address the findings in 03-review.md for the active task (see tasks/ACTIVE).
    send: false
'@
        Body = @'
You are the reviewer. You report; you do not fix.

1. Read `tasks/ACTIVE`, then every artifact in the task folder and `AGENTS.md`.
2. Inspect the actual changes with `git status` and `git diff`. Do not trust `02-implementation.md` alone.
3. Run the test, lint, and type-check commands from `AGENTS.md`.
4. Check: conformance to the plan and acceptance criteria, correctness, edge cases,
   test coverage, security, unrequested scope creep.
5. Write `03-review.md` using `tasks/_template/03-review.md`.
   Every finding needs a severity (blocker/major/minor), a file:line, and a suggested fix.
6. Set frontmatter `status: approved` only if there are no blockers or majors.
   Otherwise set `status: changes_requested`.

The only file you may create or modify is `03-review.md`. Never edit source code.
'@
    }
)

foreach ($r in $roles) {
    # VS Code / GitHub Copilot format
    $vs = "---`nname: $($r.Name)`ndescription: `"$($r.Desc)`"`ntools: $($r.VsTools)`n" +
          "# model: <Model Name> (copilot)   # pin a model per role; use the exact name from the model picker`n" +
          "$($r.Handoffs)`n---`n`n$($r.Body)"
    W ".github/agents/$($r.File).agent.md" $vs

    # Claude Code format (optional)
    if ($Claude) {
        $cc = "---`nname: $($r.File)`ndescription: `"$($r.Desc)`"`ntools: $($r.ClaudeTools)`nmodel: $($r.ClaudeModel)`n---`n`n$($r.Body)"
        W ".claude/agents/$($r.File).md" $cc
    }
}

# ------------------------------------------------------------ gitignore
$gi = Join-Path $Root ".gitignore"
$line = "tasks/ACTIVE"
if (-not (Test-Path $gi) -or -not (Select-String -Path $gi -SimpleMatch $line -Quiet)) {
    [System.IO.File]::AppendAllText($gi, "`n$line`n", $utf8)
    Write-Host "update .gitignore"
}

Write-Host ""
Write-Host "Done. Next:"
Write-Host "  1. Fill in the conventions section of AGENTS.md (test/lint commands)."
Write-Host "  2. .\scripts\new-task.ps1 `"My first task`""
Write-Host "  3. Edit tasks/<name>/00-brief.md, then pick the Planner agent in Copilot Chat."