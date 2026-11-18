#!/usr/bin/env bash
# Scaffolds a planner/coder/reviewer workflow with per-task artifacts.
# Usage (from repo root):
#   bash scaffold-agents.sh [--root <path>] [--claude] [--force]
set -euo pipefail

ROOT="."
CLAUDE=0
FORCE=0

usage() {
    cat <<'EOF'
Usage: scaffold-agents.sh [--root <path>] [--claude] [--force]

  --root <path>  Target repo (default: current directory)
  --claude       Also generate .claude/agents/ (Claude Code format)
  --force        Overwrite existing files (default: skip them)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)   ROOT="${2:?--root needs a path}"; shift ;;
        --claude) CLAUDE=1 ;;
        --force)  FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

ROOT="$(cd "$ROOT" && pwd)"

# w <relative-path>  -- writes stdin to the file, skipping if it exists (unless --force)
w() {
    local rel="$1" full="$ROOT/$1"
    if [[ -e "$full" && $FORCE -eq 0 ]]; then
        echo "skip   $rel"
        cat > /dev/null
        return
    fi
    mkdir -p "$(dirname "$full")"
    cat > "$full"
    echo "create $rel"
}

# ------------------------------------------------------------ repo-wide docs
w AGENTS.md <<'EOF'
# Agent conventions

## Workflow
Every coding task runs through three roles, handing off via files in `tasks/<task>/`:

1. **Planner** reads `00-brief.md`, writes `01-plan.md`. Never edits source.
2. **Coder** reads the plan, implements it, writes `02-implementation.md`.
3. **Reviewer** reads everything plus the diff, writes `03-review.md`. Never fixes code.

The active task folder name is in `tasks/ACTIVE`. Create a task with:
`./scripts/new-task.sh "Short task title"`

Files are the handoff. Do not rely on chat history; re-read the artifacts.

## Project conventions
<!-- Fill in. Agents read this file. -->
- Language / framework:
- Install:
- Test command:
- Lint / format command:
- Type check command:
- Code style notes:
EOF

w .github/copilot-instructions.md <<'EOF'
Follow `AGENTS.md` for workflow and project conventions.
Task artifacts live in `tasks/<task>/`; the active task is named in `tasks/ACTIVE`.
EOF

# ------------------------------------------------------------ task templates
w tasks/_template/00-brief.md <<'EOF'
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
EOF

w tasks/_template/01-plan.md <<'EOF'
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
EOF

w tasks/_template/02-implementation.md <<'EOF'
# Implementation

## Steps completed
<!-- Reference plan step numbers. -->

## Deviations from plan
<!-- Every departure, with the reason. "None" if none. -->

## Files changed
## Commands run
## Test results
## Known gaps
EOF

w tasks/_template/03-review.md <<'EOF'
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
EOF

# ------------------------------------------------------------ new-task helper
w scripts/new-task.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: $0 \"Task title\"" >&2; exit 1; }
title="$*"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
[[ -n "$slug" ]] || { echo "Title must contain letters or digits" >&2; exit 1; }

name="$(date +%F)-$slug"
dest="$root/tasks/$name"
[[ ! -e "$dest" ]] || { echo "Task already exists: $name" >&2; exit 1; }

cp -r "$root/tasks/_template" "$dest"
content="$(<"$dest/00-brief.md")"
printf '%s\n' "${content//'{{TITLE}}'/"$title"}" > "$dest/00-brief.md"
printf '%s' "$name" > "$root/tasks/ACTIVE"

echo "Created tasks/$name (now active)"
echo "Next: fill in 00-brief.md, then switch to the Planner agent."
EOF
chmod +x "$ROOT/scripts/new-task.sh" 2>/dev/null || true

w .github/prompts/new-task.prompt.md <<'EOF'
---
description: Create a new task folder and make it active
agent: agent
tools: ['execute']
---
Run `./scripts/new-task.sh "${input:title:Short task title}"` in the terminal,
then report the created folder name. Do nothing else.
EOF

# ------------------------------------------------------------ agent definitions
# emit_role <Name> <file> <description> <vscode-tools> <claude-tools> <claude-model> <handoffs> <body>
emit_role() {
    local name="$1" file="$2" desc="$3" vs_tools="$4" cc_tools="$5" cc_model="$6" handoffs="$7" body="$8"

    # VS Code / GitHub Copilot format
    {
        printf -- '---\nname: %s\ndescription: "%s"\ntools: %s\n' "$name" "$desc" "$vs_tools"
        printf '# model: <Model Name> (copilot)   # pin a model per role; use the exact name from the model picker\n'
        printf '%s' "$handoffs"
        printf -- '---\n\n%s' "$body"
    } | w ".github/agents/$file.agent.md"

    # Claude Code format (optional)
    if [[ $CLAUDE -eq 1 ]]; then
        printf -- '---\nname: %s\ndescription: "%s"\ntools: %s\nmodel: %s\n---\n\n%s' \
            "$file" "$desc" "$cc_tools" "$cc_model" "$body" | w ".claude/agents/$file.md"
    fi
}

IFS= read -r -d '' PLANNER_HANDOFFS <<'EOF' || true
handoffs:
  - label: Implement plan
    agent: Coder
    prompt: Implement the plan in the active task folder (see tasks/ACTIVE).
    send: false
EOF

IFS= read -r -d '' PLANNER_BODY <<'EOF' || true
You are the planner. You never modify source code.

1. Read `tasks/ACTIVE` for the active folder name, then `tasks/<name>/00-brief.md` and `AGENTS.md`.
2. Explore the codebase to understand the affected areas.
3. Write `tasks/<name>/01-plan.md` using the structure in `tasks/_template/01-plan.md`.
4. List concrete files, ordered steps, risks, and a test plan.
5. Put unresolved questions under "Open questions" and ask the user. Set `status: ready` only when none remain.

The only file you may create or modify is `01-plan.md`.
EOF

IFS= read -r -d '' CODER_HANDOFFS <<'EOF' || true
handoffs:
  - label: Review implementation
    agent: Reviewer
    prompt: Review the implementation for the active task (see tasks/ACTIVE).
    send: false
EOF

IFS= read -r -d '' CODER_BODY <<'EOF' || true
You are the coder.

1. Read `tasks/ACTIVE`, then `01-plan.md` and `AGENTS.md`. If the plan is not `status: ready`, stop and say so.
2. Implement the steps in order. Do not expand scope beyond the plan.
3. Run the test, lint, and type-check commands from `AGENTS.md`. Fix failures you caused.
4. Write `02-implementation.md` using `tasks/_template/02-implementation.md`.
   Log every deviation from the plan with the reason.

If `03-review.md` exists with `status: changes_requested`: address each finding,
then append a `## Round N` section to `02-implementation.md` describing the fixes.

Never edit `00-brief.md`, `01-plan.md`, or `03-review.md`.
EOF

IFS= read -r -d '' REVIEWER_HANDOFFS <<'EOF' || true
handoffs:
  - label: Send findings to coder
    agent: Coder
    prompt: Address the findings in 03-review.md for the active task (see tasks/ACTIVE).
    send: false
EOF

IFS= read -r -d '' REVIEWER_BODY <<'EOF' || true
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
EOF

emit_role "Planner" "planner" \
    "Produces an implementation plan from the task brief. Never edits source code." \
    "['read', 'search', 'web', 'edit']" \
    "Read, Grep, Glob, Write" "opus" \
    "$PLANNER_HANDOFFS" "$PLANNER_BODY"

emit_role "Coder" "coder" \
    "Implements the approved plan and records what changed." \
    "['read', 'search', 'edit', 'execute']" \
    "Read, Grep, Glob, Edit, Write, Bash" "sonnet" \
    "$CODER_HANDOFFS" "$CODER_BODY"

emit_role "Reviewer" "reviewer" \
    "Reviews the implementation against the plan and brief. Reports findings, never fixes code." \
    "['read', 'search', 'edit', 'execute']" \
    "Read, Grep, Glob, Bash, Write" "sonnet" \
    "$REVIEWER_HANDOFFS" "$REVIEWER_BODY"

# ------------------------------------------------------------ gitignore
gi="$ROOT/.gitignore"
if ! grep -qxF "tasks/ACTIVE" "$gi" 2>/dev/null; then
    printf '\ntasks/ACTIVE\n' >> "$gi"
    echo "update .gitignore"
fi

echo
echo "Done. Next:"
echo "  1. Fill in the conventions section of AGENTS.md (test/lint commands)."
echo "  2. ./scripts/new-task.sh \"My first task\""
echo "  3. Edit tasks/<name>/00-brief.md, then pick the Planner agent in Copilot Chat."
