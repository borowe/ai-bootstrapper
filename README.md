# Multi-Agent Dev Toolkit

Two independent toolkits, each with a PowerShell and a bash script:

| Toolkit | Scripts | Purpose |
| --- | --- | --- |
| **Application starter** | `bootstrap.ps1` / `bootstrap.sh` | New Python project: FastAPI, Pydantic AI, Langfuse tracing, model routing, tests, **one example agent**, and a `README.md` for the generated project |
| **Editor workflow** | `scaffold-agents.ps1` / `scaffold-agents.sh` | Setup, Orchestrator, Planner, Coder and Reviewer agents for **VS Code Copilot Chat**, with saved artifacts per task and a `user_guide_for_agents.md` |

They do different jobs and share no code. Use either or both.

- **Application starter**: agents run *inside your app* at runtime, call model APIs with your keys, and return typed results.
- **Editor workflow**: agents run *in your editor* while you write code. They are prompt files, not Python.

If you only want a better personal coding workflow, run **only** `scaffold-agents`. Skip `bootstrap`.

---

## Prerequisites

| Need | For | Install |
| --- | --- | --- |
| [uv](https://docs.astral.sh/uv/) | bootstrap | `winget install astral-sh.uv` (Windows) or `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| Git | both | `winget install Git.Git` |
| VS Code (current) with GitHub Copilot | scaffold-agents | [code.visualstudio.com](https://code.visualstudio.com) |
| Anthropic and/or OpenAI API key | bootstrap | Provider console |

**PowerShell vs bash:** use the `.ps1` scripts on native Windows. Use the `.sh` scripts on macOS, Linux, WSL, or Git Bash. Outputs are equivalent, except the generated task helper matches your shell (`new-task.ps1` vs `new-task.sh`).

If PowerShell blocks scripts, use the `-ExecutionPolicy Bypass -File` form below. It applies only to that invocation.

---

## 1. Application starter: `bootstrap`

```powershell
# PowerShell
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 [project-name]
```
```bash
# bash
bash bootstrap.sh [project-name]
```

`project-name` defaults to `agentkit`. The script creates a **new folder**, so run it from the parent directory.

### What it does
1. `uv init` with Python 3.12
2. Installs `fastapi[standard]`, `pydantic-ai-slim[anthropic,openai,mcp]`, `langfuse`, `pydantic-settings`, `httpx`, `pydantic-evals`
3. Installs dev tools: `pytest`, `pytest-asyncio`, `ruff`, `pyright`, `pre-commit`
4. Writes the project files and a **project `README.md`** (named after your project), copies `.env.example` to `.env`, runs `git init`
5. Installs pre-commit hooks and runs the tests as a smoke check

### Generated layout
```
README.md                # setup, run, endpoints, config, testing, how to add an agent
app/
  config.py              # pydantic-settings: model per role, budgets, keys
  models.py              # build_model(role): native provider or LiteLLM gateway
  observability.py       # Langfuse tracing via Agent.instrument_all()
  schemas.py             # NewsItem
  tools/google_news.py   # Google News RSS search (no API key)
  agents/news.py         # the example agent
  api/routes.py          # GET /health, GET /news
  main.py
tests/                   # no real model or network calls
litellm_config.yaml      # optional shared gateway
.env / .env.example
```

### The example agent
`app/agents/news.py` answers **"what's the latest in fintech ai?"** by calling a `google_news_search` tool and returning the first result as a typed `NewsItem` (`title`, `url`, `source`, `published`).

The tool reads Google News's public RSS feed, so no search API key is needed. Only your model key is.

```bash
# Add ANTHROPIC_API_KEY to .env, then:
uv run python -m app.agents.news              # one-off run, no server
uv run fastapi dev app/main.py                # start the API
```
```powershell
Invoke-RestMethod http://localhost:8000/news
Invoke-RestMethod "http://localhost:8000/news?question=latest%20in%20open%20banking"
```
```bash
curl localhost:8000/news
```

Interactive API docs: http://localhost:8000/docs

**Caveats:** the RSS feed is unofficial and Google can change or rate-limit it. Result links are Google redirect URLs. For production, swap `app/tools/google_news.py` for a licensed news API; the agent code doesn't change.

### Day-to-day commands
```
uv run pytest                 # tests (no network, no model calls)
uv run ruff check . --fix     # lint
uv run ruff format .          # format
uv run pyright                # type check
```

### Configuration (`.env`)
| Variable | Purpose |
| --- | --- |
| `DEFAULT_MODEL` | `provider:model` for the `default` role. Swap models here, not in code |
| `GATEWAY_URL`, `GATEWAY_KEY` | If set, all roles route through a LiteLLM proxy; the role name is the model alias |
| `MAX_REQUESTS`, `MAX_TOKENS` | Hard budget per agent run |
| `LANGFUSE_*` | Tracing. Leave blank to disable |

The generated project's own `README.md` documents all of this plus how to add an agent or a model role, so it travels with the codebase.

---

## 2. Editor workflow: `scaffold-agents`

Run from the **root of the repo** you want to add it to. It works on any repo, not just ones created by `bootstrap`.

```powershell
# PowerShell
powershell -ExecutionPolicy Bypass -File .\scaffold-agents.ps1 [-Root <path>] [-Claude] [-Force]
```
```bash
# bash
bash scaffold-agents.sh [--root <path>] [--claude] [--force]
```

| Flag (PowerShell / bash) | Effect |
| --- | --- |
| `-Root` / `--root` | Target repo. Defaults to the current directory |
| `-Claude` / `--claude` | Also generate `.claude/agents/` for Claude Code |
| `-Force` / `--force` | Overwrite existing files. Without it, existing files are skipped |

Re-running without the force flag is safe: it skips existing files and adds only what is missing. That is how you pick up new agents in a repo you already scaffolded.

### What it creates
```
AGENTS.md                          # conventions all agents read
user_guide_for_agents.md           # how to use the agents day to day
.github/
  copilot-instructions.md          # points to AGENTS.md
  agents/
    setup.agent.md                 # guided first-time setup
    orchestrator.agent.md          # runs plan -> code -> review automatically
    planner.agent.md
    coder.agent.md
    reviewer.agent.md
  skills/new-task/SKILL.md         # the /new-task command
scripts/new-task.ps1 | new-task.sh # creates a task folder
tasks/
  _template/                       # 00-brief, 01-plan, 02-implementation, 03-review
  ACTIVE                           # name of the current task (gitignored)
.claude/agents/                    # only with -Claude / --claude
```

### The agents

| Agent | Role |
| --- | --- |
| **Setup** | Walks you through first-time setup, one step at a time. Each step is labeled Required or Optional; Optional steps can be skipped |
| **Orchestrator** | Runs Planner, Coder and Reviewer as subagents, pausing for your plan approval |
| **Planner** | Writes `01-plan.md` from your brief. Never edits source |
| **Coder** | Implements the plan, writes `02-implementation.md` |
| **Reviewer** | Reads the real diff, runs checks, writes `03-review.md`. Never fixes code |

### First-time setup: the Setup agent
Select **Setup** in Copilot Chat and say "start". It detects your project and asks:

| Step | Needed? | If you skip |
| --- | --- | --- |
| Detect project | Required (automatic) | n/a |
| Test, lint, type-check commands | Required: give a command or answer "none" | "none" means that check never runs |
| Language and install command | Required (confirm detection) | n/a |
| Verify the commands run | Optional | Commands are saved unverified |
| Code style notes | Optional | Agents use general judgment |
| Pin a model per role | Optional | Agents use your model picker's model |
| Claude Code models | Optional (only if `.claude/agents/` exists) | n/a |
| Environment check | Optional | n/a |

"Required" means the question gets answered so `AGENTS.md` is never left blank. It does not force a specific answer. You can re-run Setup any time.

### Workflow
```powershell
.\scripts\new-task.ps1 "Add rate limiting"      # PowerShell
```
```bash
./scripts/new-task.sh "Add rate limiting"        # bash
```
You can also type `/new-task` in chat.

1. Fill in `tasks/<date>-add-rate-limiting/00-brief.md`: goal, constraints, acceptance criteria.
2. Run it, either way:
   - **Automated:** select **Orchestrator** and say "Run the active task."
   - **Manual:** select **Planner** and use the handoff buttons.

Each agent reads the previous artifact from disk, not from chat history, so every handoff starts with clean context. The full walkthrough is in the generated `user_guide_for_agents.md`.

### Automated mode: the Orchestrator
Handoff buttons are manual by design: one agent cannot call another. For a hands-off run, the Orchestrator runs the others as **subagents**, deciding each step from the files in the task folder.

1. It runs the Planner, summarizes the plan, then **stops for your approval**.
2. Reply "approved" (or edit `01-plan.md` to `status: ready` and say "continue").
3. It loops Coder, then Reviewer, up to 3 rounds, and stops when `03-review.md` is `approved`.

Subagents run autonomously and cannot ask you questions mid-run, so the Planner records open questions in the plan and the Orchestrator relays them.

**Where to check Run Subagent:** select the Orchestrator agent, then open **Configure Tools** (the tools button in the Chat view's input area; its exact position varies by VS Code version) and make sure **Run Subagent** is checked. The Orchestrator's own `tools:` list already requests it, so this is a check, not usually a fix.

### Notes
- **Tool limits are enforced by prompt, not by path.** Planner, reviewer, orchestrator and setup have `edit` access because they must write specific files, and their instructions restrict them to those files. If one ever touches source, check `git diff`.
- **Commit** `01-plan.md` and `03-review.md` as design records. `tasks/ACTIVE` is gitignored.
- **Switch tasks** by changing the contents of `tasks/ACTIVE`.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "running scripts is disabled" | Use the `-ExecutionPolicy Bypass -File` form |
| `uv` not found | Install it, then open a new terminal |
| Agents missing from the VS Code picker | Run **Chat: Configure Custom Agents** and look for a frontmatter error. Update VS Code |
| Orchestrator can't run the other agents | Check **Run Subagent** under Configure Tools (see above). Agent names are case-sensitive |
| No handoff buttons | Handoffs are VS Code only and need a current version |
| Copilot offers to migrate a prompt to a skill | See below |
| bootstrap's final `pytest` fails | pydantic-ai renames APIs between minor releases. Check `OpenAIChatModel`, `output_type`, `UsageLimits`, and `TestModel(call_tools=...)` against your installed version. `uv.lock` pins what you got |
| `/news` returns 502 | The Google News fetch failed (network, or Google throttling). Retry, or swap the tool for a news API |
| Odd characters or parse errors in `.env` | Save as UTF-8 without BOM. VS Code is fine |
| `curl` misbehaves in PowerShell | It aliases `Invoke-WebRequest`. Use `Invoke-RestMethod` |
| Bash scripts fail on Windows | Run them in WSL or Git Bash, or use the `.ps1` versions |
| A pinned model makes an agent fail | The name must match the model picker exactly. Re-run Setup or delete the `model:` line |

### Why Copilot asks to migrate a prompt to a skill
VS Code is moving toward the **Copilot harness**, which doesn't load `*.prompt.md` files; prompt files only run in the Local harness. Earlier versions of these scripts shipped `/new-task` as `.github/prompts/new-task.prompt.md`, so VS Code offers to convert it.

**What changed in the scripts:** they now generate `/new-task` as a skill at `.github/skills/new-task/SKILL.md`, which works in either harness. It is marked `disable-model-invocation: true`, so Copilot only runs it when you invoke it and never auto-selects it. One difference: the old prompt asked for the title through a form field; the skill has the agent ask for it instead.

**If you already scaffolded:** re-run the scaffold script (without the force flag) to add the skill. It prints a note if the old prompt file is still there. Delete the old file to avoid a duplicate `/new-task`.

**Custom agents (`.agent.md`) are not prompt files** and aren't affected by that prompt, but handoffs and subagents are described in VS Code's docs for the Local harness. If you move to the Copilot harness, test the agents in a fresh chat.

If you're on the Local harness, keeping the prompt file would also work. The skill is simply the option that survives the transition.

If both toolkits seem to define "agents", they are unrelated. `app/agents/` is Python run by your application. `.github/agents/` is Copilot Chat configuration.

---

## Verification status

- `scaffold-agents.sh`: executed end to end in clean and legacy directories (including with a leftover prompt file), plus `new-task.sh` and the re-run (skip) behavior.
- `bootstrap.sh`: executed with a stubbed `uv`. Generated files compile and the project README is created with the project name filled in. The RSS parser logic was checked against a sample feed.
- **Not executed:** the PowerShell scripts, any live Copilot Chat behavior (Setup, Orchestrator, handoffs, the skill), and anything needing `pydantic-ai`, live model calls, or network access. The first real checks are bootstrap's final `pytest` step and a fresh Copilot chat with the Setup agent.

---

## Next steps

- Add `pydantic-evals` cases under `evals/` and run them on every model swap.
- Expose tools to agents through MCP (`pydantic-ai-slim[mcp]` is already installed).
- Turn on tracing by filling in the `LANGFUSE_*` keys.
- Add LangGraph only when you need persistent state or branching.
