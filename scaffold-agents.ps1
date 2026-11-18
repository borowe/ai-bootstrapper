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

First time in this repo? Select the **Setup** agent to configure project commands and models.
For a hands-off run, select the **Orchestrator** agent. Details: `user_guide_for_agents.md`.

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

W ".github/skills/new-task/SKILL.md" @'
---
name: new-task
description: Create a new task folder under tasks/ and make it the active task. Use when the user asks to start, create, or scaffold a new coding task.
disable-model-invocation: true
---
Create a new task:

1. If the user has not given a short task title, ask for one.
2. Run `.\scripts\new-task.ps1 "<title>"` in the terminal.
3. Report the created folder name and remind the user to fill in `00-brief.md`.

Do nothing else.
'@

if (Test-Path (Join-Path $Root ".github/prompts/new-task.prompt.md")) {
    Write-Host "note   .github/prompts/new-task.prompt.md is superseded by the new-task skill; you can delete it"
}

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

# ------------------------------------------------------------ orchestrator (runs the three as subagents)
W ".github/agents/orchestrator.agent.md" @'
---
name: Orchestrator
description: "Runs the full task pipeline (plan, approval gate, code, review) by delegating to the Planner, Coder and Reviewer subagents."
tools: ['agent', 'read', 'search', 'edit']
agents: ['Planner', 'Coder', 'Reviewer']
# model: <Model Name> (copilot)   # pin a model per role; use the exact name from the model picker
---
You orchestrate a three-stage workflow. You never plan, write code, or review yourself.
You delegate each stage to a subagent and choose the next step from the files on disk.
Agent names are case-sensitive: Planner, Coder, Reviewer.

## Determine state
Read `tasks/ACTIVE`, then inspect `tasks/<name>/`:

- **No `01-plan.md`**: run the Planner subagent, then stop at the approval gate.
- **`01-plan.md` has `status: draft`**: if the user's latest message clearly approves the plan
  ("approved", "go", "looks good"), change only that frontmatter line to `status: ready`
  and start the build loop. Otherwise stop and ask for approval or changes.
- **`01-plan.md` has `status: ready`**: start the build loop.
- **`03-review.md` has `status: approved`**: report completion.

## Planner prompt
"Plan the active task (folder named in tasks/ACTIVE). Write 01-plan.md. Do not wait for answers:
record unresolved questions under Open questions and list them in your final message."

## Approval gate
After the Planner finishes: summarize the plan in a few lines, list any open questions, and ask
the user to review `01-plan.md` and reply "approved" or request changes.
Never start the Coder without explicit approval in this chat. Never mark the plan ready on your own.
If the user requests changes, re-run the Planner with their feedback in the prompt.

## Build loop (max 3 rounds)
1. Run the Coder subagent. Prompt: "Implement the active task per 01-plan.md. If 03-review.md
   has status changes_requested, address its findings."
2. Run the Reviewer subagent. Prompt: "Review the active task."
3. Read the `status` in `03-review.md`:
   - `approved`: stop and report.
   - `changes_requested`: next round.

After 3 rounds without approval, stop and report the unresolved findings.

## Rules
- One subagent at a time, in order. Never in parallel.
- Subagents read artifacts from disk. Do not pass chat history.
- After each subagent, confirm its artifact exists (`02-implementation.md`, `03-review.md`).
  If missing, re-run once, then report the failure.
- Final report: task name, plan status, review status, rounds used, files changed
  (from `02-implementation.md`), and any unresolved findings.
- The only edit you may make is the `status` line in `01-plan.md`.
'@

# ------------------------------------------------------------ setup agent
W ".github/agents/setup.agent.md" @'
---
name: Setup
description: "Walks you through first-time setup: project commands (test, lint, type-check), per-role models, and conventions. Optional steps can be skipped."
tools: ['read', 'search', 'edit', 'execute']
disable-model-invocation: true
handoffs:
  - label: Run a task end to end
    agent: Orchestrator
    prompt: Run the active task (see tasks/ACTIVE).
    send: false
---
You are the setup guide. You configure this repository for the planner/coder/reviewer workflow
by asking short questions, then editing a few files. You never modify source code.

## Ground rules
- Ask ONE step at a time. Keep questions short and offer numbered choices where possible.
- Label every step **Required** or **Optional**. For Optional steps, say so up front and accept
  "skip" at any time. Skipping is always fine; say in one phrase what skipping means.
- "Required" never forces a specific answer. For commands, "none" is a valid answer. It means the
  question must be answered so the files are not left blank.
- Propose defaults from what you detect in the repo. The user confirms or edits.
  Never invent a command you have no evidence for.
- You may edit only: the "Project conventions" section of `AGENTS.md`, the `model:` line in
  `.github/agents/*.agent.md`, and (if present) the `model:` line in `.claude/agents/*.md`.
  Show the exact change before writing it.
- Setup can be re-run. At the start, read `AGENTS.md` and `.github/agents/*.agent.md`, report what
  is already configured, and ask what to revisit.

## Steps

### 1. Detect the project (Required, automatic)
Inspect the repo root for manifests and tooling, such as `pyproject.toml`, `package.json`, `go.mod`,
`Cargo.toml`, `*.csproj`, `Makefile`, `justfile`, and CI workflows in `.github/workflows`.
Summarize in three lines: language/framework, package manager, and the commands you found.
Ask the user to confirm or correct.

### 2. Verification commands (Required: a command, or "none")
For each, propose the detected command and ask the user to confirm, change, or answer "none":
- Test command
- Lint / format command
- Type-check command

Explain once: the Coder and Reviewer run these. A "none" means that check is skipped and reviews
rely on reading the code alone. Write results into the matching lines under "Project conventions"
in `AGENTS.md`. Record "none" as `none (skipped)`; never leave a blank.

### 3. Language, framework and install command (Required: confirm detection)
Fill the "Language / framework" and "Install" lines from step 1.

### 4. Confirm the commands work (Optional)
Offer to run each confirmed command once. Run only with explicit permission, one at a time, and
report pass or fail. If one fails, offer to correct the entry or keep it. Unverified commands are
still saved. Skipping is fine.

### 5. Code style notes (Optional)
Ask for conventions the agents should follow: naming, formatting rules, banned libraries, folder
structure. Save them under "Code style notes". Skipping leaves the line empty.

### 6. Models per role (Optional)
Explain: by default every agent uses whichever model is selected in the Copilot Chat model picker.
Pinning a model per role is optional.
- Ask the user to open the model picker and give you the exact model names they want for Planner,
  Coder and Reviewer. They may pin only some roles. The Orchestrator can be pinned too.
- Offer guidance, not specific names: a strong reasoning model for the Planner, a fast capable
  coding model for the Coder, and a different model family for the Reviewer for a more independent
  review.
- For each pinned role, replace the commented `# model:` line in `.github/agents/<role>.agent.md`
  with `model: <name> (copilot)`, using the name exactly as given.
- Warn that a wrong name can make an agent fall back to the default or fail to load. Suggest
  testing in a fresh chat.
- Skipping keeps the picker's model.

### 7. Claude Code agents (Optional, only if `.claude/agents/` exists)
Ask whether they use Claude Code. If so, offer to set `model:` in `.claude/agents/*.md` (for
example `opus`, `sonnet`, `haiku`). Otherwise skip.

### 8. Environment check (Optional)
You cannot check these yourself, so tell the user:
- VS Code and the Copilot extension should be current.
- With the Orchestrator selected, the Configure Tools list should have **Run Subagent** enabled.
  Automated mode needs it. Manual handoff mode does not.

## Finish
Print a summary table: each step, its status (Configured, Skipped, Detected) and, for skipped
items, the consequence in one phrase. Then give next steps:
1. Create a task with the `/new-task` skill or the `scripts/new-task` script.
2. Fill in `tasks/<name>/00-brief.md`.
3. Select **Orchestrator** (automated, pauses for plan approval) or **Planner** (manual handoffs).

Point to `user_guide_for_agents.md` for details.
'@

# ------------------------------------------------------------ user guide
W "user_guide_for_agents.md" @'
# Agent workflow user guide

How to use the Setup, Orchestrator, Planner, Coder and Reviewer agents in this repo.
They run in **GitHub Copilot Chat** in VS Code and pass work to each other through files, not chat history.

## The agents

| Agent | Role | Writes |
| --- | --- | --- |
| **Setup** | One-time guided configuration (commands, models, conventions) | `AGENTS.md`, `model:` lines |
| **Orchestrator** | Runs the whole pipeline automatically, pausing for plan approval | `status` line in `01-plan.md` |
| **Planner** | Turns a brief into a plan. Never edits source | `01-plan.md` |
| **Coder** | Implements the approved plan | source, `02-implementation.md` |
| **Reviewer** | Checks the work against the plan and the diff. Never fixes code | `03-review.md` |

## 1. First-time setup
Select the **Setup** agent in Copilot Chat and say "start". It walks you through, one step at a time:

| Step | Needed? | If you skip |
| --- | --- | --- |
| Detect project | Required (automatic) | n/a |
| Test, lint, type-check commands | Required: a command or "none" | "none" means that check never runs |
| Language and install command | Required (confirm detection) | n/a |
| Verify commands run | Optional | Commands are saved unverified |
| Code style notes | Optional | Agents use general judgment |
| Pin a model per role | Optional | Agents use your model picker's model |
| Claude Code models | Optional | n/a |
| Environment check | Optional | n/a |

You can re-run Setup any time to change answers. You can also edit `AGENTS.md` by hand.

## 2. Create a task
```
./scripts/new-task.sh "Add rate limiting"        # bash
.\scripts\new-task.ps1 "Add rate limiting"       # PowerShell
```
Or type `/new-task` in chat. This creates `tasks/<date>-add-rate-limiting/` from the template and
makes it the active task (its name is stored in `tasks/ACTIVE`).

Open `00-brief.md` and fill in the goal, constraints, and acceptance criteria. A clear brief is the
biggest factor in result quality.

## 3. Run the task

### Automated: Orchestrator (recommended)
1. Select **Orchestrator** and say "Run the active task."
2. It runs the Planner, summarizes the plan, lists open questions, then **stops**.
3. Review `01-plan.md`. Reply "approved", or ask for changes and it re-plans.
   (You can also set `status: ready` in the file yourself and say "continue".)
4. It loops Coder, then Reviewer, up to 3 rounds, until the review says `approved`.
5. It reports the outcome: plan status, review status, rounds used, files changed, open findings.

### Manual: handoff buttons
Select **Planner**, then click **Implement plan** to move to the **Coder**, then
**Review implementation** to move to the **Reviewer**. If changes are requested, use
**Send findings to coder**. You stay in control of every step.

## Task folder anatomy
```
tasks/2026-11-17-add-rate-limiting/
  00-brief.md            you: goal, constraints, acceptance criteria
  01-plan.md             planner: steps, files, risks, test plan   (status: draft | ready)
  02-implementation.md   coder: what changed, deviations, commands run
  03-review.md           reviewer: findings                        (status: approved | changes_requested)
tasks/ACTIVE             name of the current task (gitignored)
```
Commit `01-plan.md` and `03-review.md` as design records. To switch tasks, change the contents of `tasks/ACTIVE`.

## Configuration
- **`AGENTS.md`**: project conventions every agent reads (commands, style). Edit it directly or through Setup.
- **Models**: pin per role with the `model:` line in each `.github/agents/*.agent.md`, or leave unpinned to use your picker's model.
  A different model family for the Reviewer gives a more independent review.
- **Agent behavior**: the agent files are plain Markdown. Edit the instructions to change how each role works.

## Tips
- Keep tasks small enough to review in one sitting. Split large work into several tasks.
- Put unresolved decisions in the brief or answer the Planner's open questions before approving.
- Read `03-review.md` yourself before merging. The Reviewer is a second opinion, not a gate.
- If an agent edits something it shouldn't, check `git diff`. Path limits are enforced by instructions, not by tool permissions.

## Troubleshooting and FAQ

**An agent doesn't appear in the picker.**
Run **Chat: Configure Custom Agents** in the Command Palette and look for a frontmatter error. Confirm VS Code is current.

**The Orchestrator says it can't run the other agents.**
It needs the **Run Subagent** tool. Select the Orchestrator, then open **Configure Tools** (the tools button in the chat input area; its position varies by VS Code version) and make sure **Run Subagent** is checked. Agent names are case-sensitive (`Planner`, `Coder`, `Reviewer`).

**Copilot offers to migrate a prompt to a skill.**
VS Code is moving toward the Copilot harness, which doesn't load `*.prompt.md` files. This repo ships `/new-task` as a skill so it works in either harness. If you still have `.github/prompts/new-task.prompt.md` from an earlier scaffold, delete it to avoid a duplicate command.

**Do these agents work in the Copilot harness?**
They are written for VS Code's Local harness. Handoffs and subagents may behave differently in other harnesses. Test in a fresh chat, and see VS Code's "Migrate customizations to the Copilot harness" guide if you switch.

**The Orchestrator won't continue.**
It needs `status: ready` in `01-plan.md`, set when you reply "approved" or when you edit it yourself. Check the file's frontmatter.

**Setup changed a model and the agent stopped working.**
The model name probably didn't match the picker exactly. Re-run Setup, or edit the `model:` line in the agent file. Remove the line to fall back to the default.

## Files reference
```
AGENTS.md                          conventions (shared by all agents)
user_guide_for_agents.md           this guide
.github/
  copilot-instructions.md          points Copilot to AGENTS.md
  agents/                          setup, orchestrator, planner, coder, reviewer
  skills/new-task/SKILL.md         the /new-task command
scripts/new-task.*                 creates a task folder
tasks/_template/                   templates for the four artifacts
```
'@

# ------------------------------------------------------------ gitignore
$gi = Join-Path $Root ".gitignore"
$line = "tasks/ACTIVE"
if (-not (Test-Path $gi) -or -not (Select-String -Path $gi -SimpleMatch $line -Quiet)) {
    [System.IO.File]::AppendAllText($gi, "`n$line`n", $utf8)
    Write-Host "update .gitignore"
}

Write-Host ""
Write-Host "Done. Next:"
Write-Host "  1. In Copilot Chat, select the Setup agent and follow its prompts (commands, models)."
Write-Host "  2. .\scripts\new-task.ps1 `"My first task`"   (or /new-task in chat)"
Write-Host "  3. Edit tasks/<name>/00-brief.md, then select Orchestrator (automated) or Planner (manual)."
Write-Host "  Guide: user_guide_for_agents.md"
