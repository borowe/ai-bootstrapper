# Multi-Agent Dev Toolkit

Two independent toolkits, each with a PowerShell and a bash script:

| Toolkit | Scripts | Purpose |
| --- | --- | --- |
| **Application starter** | `bootstrap.ps1` / `bootstrap.sh` | New Python project with FastAPI, Pydantic AI, Langfuse tracing, a model-routing layer, tests, and **one example agent** |
| **Editor workflow** | `scaffold-agents.ps1` / `scaffold-agents.sh` | Planner / coder / reviewer agents for **VS Code Copilot Chat**, with saved artifacts per coding task |

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
| VS Code 1.106+ with GitHub Copilot | scaffold-agents (handoff buttons) | [code.visualstudio.com](https://code.visualstudio.com) |
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
4. Writes the project files, copies `.env.example` to `.env`, runs `git init`
5. Installs the Ruff and Gitleaks pre-commit hooks and runs the tests as a smoke check

### Generated layout
```
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

### Adding your own agent
1. Copy `app/agents/news.py`, change the output schema, instructions, and tools.
2. Put tool implementations in `app/tools/`, schemas in `app/schemas.py`.
3. Expose it in `app/api/routes.py`.
4. Test it with `TestModel`, as in `tests/test_agent.py`.

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

To add a role (say a cheaper model for summarization): extend `Role` in `app/models.py`, add `<role>_model` to `Settings` and `.env`, and add an alias to `litellm_config.yaml` if you use the gateway.

### Optional: LiteLLM gateway
```
uv add "litellm[proxy]"
uv run litellm --config litellm_config.yaml --port 4000
```
Then set `GATEWAY_URL=http://localhost:4000` and `GATEWAY_KEY=<litellm key or any string>`.

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

### What it creates
```
AGENTS.md                          # conventions: fill in test/lint commands
.github/
  copilot-instructions.md          # points to AGENTS.md
  agents/
    planner.agent.md
    coder.agent.md
    reviewer.agent.md
  prompts/new-task.prompt.md       # run from Copilot Chat
scripts/new-task.ps1 | new-task.sh # creates a task folder
tasks/
  _template/                       # 00-brief, 01-plan, 02-implementation, 03-review
  ACTIVE                           # name of the current task (gitignored)
.claude/agents/                    # only with -Claude / --claude
```

### First-time setup
1. Open `AGENTS.md` and fill in your **test, lint, and type-check commands**. The coder and reviewer both run them. Without them, reviews are opinion only.
2. Optional: pin a model per role by uncommenting the `# model:` line in each `.agent.md`, using the exact name from the VS Code model picker. A different model family for the reviewer gives a more independent review.

### Workflow
```powershell
.\scripts\new-task.ps1 "Add rate limiting"      # PowerShell
```
```bash
./scripts/new-task.sh "Add rate limiting"        # bash
```

1. Fill in `tasks/<date>-add-rate-limiting/00-brief.md`: goal, constraints, acceptance criteria.
2. In Copilot Chat, select the **Planner** agent. It writes `01-plan.md`. Resolve any open questions.
3. Click **Implement plan** to hand off to the **Coder**. It implements, runs checks, and writes `02-implementation.md`, logging deviations from the plan.
4. Click **Review implementation** to hand off to the **Reviewer**. It reads the real `git diff`, runs checks, and writes `03-review.md` with `status: approved` or `changes_requested`.
5. If changes were requested, click **Send findings to coder**. Repeat steps 3 to 5.

Each agent reads the previous artifact from disk, not from chat history, so every handoff starts with clean context.

### Notes
- **Tool limits are enforced by prompt, not by path.** Planner and reviewer have `edit` access because they must write their artifact files, and their instructions restrict them to that one file. If a reviewer ever touches source, check `git diff`.
- **Commit** `01-plan.md` and `03-review.md` as design records. `tasks/ACTIVE` is gitignored.
- **Switch tasks** by changing the contents of `tasks/ACTIVE`.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "running scripts is disabled" | Use the `-ExecutionPolicy Bypass -File` form |
| `uv` not found | Install it, then open a new terminal |
| Agents missing from the VS Code picker | Run **Chat: Configure Custom Agents** and look for a frontmatter error. Confirm VS Code is 1.106+ |
| No handoff buttons | Same version requirement; handoffs are VS Code only |
| bootstrap's final `pytest` fails | pydantic-ai renames APIs between minor releases. Check `OpenAIChatModel`, `output_type`, `UsageLimits`, and `TestModel(call_tools=...)` against your installed version. `uv.lock` pins what you got |
| `/news` returns 502 | The Google News fetch failed (network, or Google throttling). Retry, or swap the tool for a news API |
| Odd characters or parse errors in `.env` | Save as UTF-8 without BOM. VS Code is fine |
| `curl` misbehaves in PowerShell | It aliases `Invoke-WebRequest`. Use `Invoke-RestMethod` |
| Bash scripts fail on Windows | Run them in WSL or Git Bash, or use the `.ps1` versions |

If native Windows tooling causes persistent path or dependency issues, WSL2 plus VS Code's WSL extension is the escape hatch.

---

## Verification status

- `scaffold-agents.sh`: executed end to end in a clean directory, including `new-task.sh` and the re-run (skip) behavior.
- `bootstrap.sh`: executed with a stubbed `uv`. Generated files compile, and the RSS parser logic was checked against the sample feed.
- **Not executed:** the PowerShell scripts, and anything that needs `pydantic-ai`, live model calls, or network access. The first real check is bootstrap's final `pytest` step.

---

## Next steps

- Add `pydantic-evals` cases under `evals/` and run them on every model swap.
- Expose tools to agents through MCP (`pydantic-ai-slim[mcp]` is already installed).
- Turn on tracing by filling in the `LANGFUSE_*` keys.
- Add LangGraph only when you need persistent state or branching.
