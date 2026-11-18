# AI Development Stack Reference

A lean, modern Python stack for building AI applications with FastAPI, PydanticAI, observability, testing, and code quality tooling.

---

# Runtime Dependencies

## FastAPI

```bash
uv add "fastapi[standard]"
```

**Purpose:** Web API framework.

Provides:

- REST endpoints
- Request/response validation
- Dependency injection
- Async support
- Built-in OpenAPI/Swagger docs

You'll likely use this as the primary interface to your AI application.

---

## PydanticAI

```bash
uv add pydantic-ai
```

**Purpose:** Agent framework built around Pydantic models.

Provides:

- Structured LLM outputs
- Tool calling
- Typed agent inputs/outputs
- Provider abstraction
- Agent orchestration

Example:

```python
class ResearchResult(BaseModel):
    recommendation: str
    confidence: float
```

Instead of parsing free-form text, your AI returns strongly typed objects.

---

## Langfuse

```bash
uv add langfuse
```

**Purpose:** AI observability and tracing.

Provides:

- Prompt tracking
- Token usage tracking
- Cost monitoring
- Model performance analysis
- Agent workflow tracing

Think of this as:

```text
Application Performance Monitoring
```

for AI systems.

---

## Pydantic Settings

```bash
uv add pydantic-settings
```

**Purpose:** Typed application configuration.

Provides:

- Environment variable management
- `.env` file loading
- Type-safe configuration

Example:

```python
class Settings(BaseSettings):
    openai_api_key: str
    environment: str = "dev"
```

Avoids manually reading environment variables throughout the codebase.

---

## HTTPX

```bash
uv add httpx
```

**Purpose:** Modern HTTP client.

Provides:

- API calls
- Async HTTP support
- Request retries
- Streaming

Useful when:

- Calling external APIs
- Integrating tools into agents
- Accessing internal services

Modern replacement for many Requests-based workflows.

---

# Development Dependencies

## Pytest

```bash
uv add pytest --dev
```

**Purpose:** Test framework.

Provides:

- Unit tests
- Integration tests
- Assertions
- Test fixtures

Foundation of Python testing.

---

## Pytest Asyncio

```bash
uv add pytest-asyncio --dev
```

**Purpose:** Async test support.

Provides:

- Testing async functions
- Testing FastAPI endpoints
- Testing agents and workflows

Especially important because:

```text
FastAPI
PydanticAI
HTTPX
```

are all async-first.

---

## Pyright

```bash
uv add pyright --dev
```

**Purpose:** Static type checking.

Provides:

- Type validation
- Contract verification
- Early error detection

Example:

```python
def get_price() -> float:
    return "100"
```

Pyright catches this before runtime.

Pairs extremely well with:

```text
Pydantic
Typed Agent Outputs
FastAPI Schemas
```

---

## Pydantic Evals

```bash
uv add pydantic-evals --dev
```

**Purpose:** LLM evaluation framework.

Provides:

- Regression testing for prompts
- Model comparison
- Evaluation datasets
- Repeatable scoring

Useful for validating behavior when:

- Swapping models
- Modifying prompts
- Changing tools

Prevents "it seems to work" testing.

---

## Ruff

```bash
uv add ruff --dev
```

**Purpose:** Linter and formatter.

Provides:

- Style enforcement
- Static analysis
- Automatic formatting
- Import cleanup

Replaces much of the traditional:

```text
Flake8
isort
Black
```

toolchain.

Recommended to run automatically on save.

---

## Pre-Commit

```bash
uv add pre-commit --dev
```

**Purpose:** Run checks before commits.

Provides:

- Automated quality gates
- Secret scanning
- Formatting enforcement
- Lint enforcement

Typical workflow:

```text
git commit
    ↓
Run Ruff
    ↓
Run Secret Scanner
    ↓
Allow Commit
```

Commonly combined with:

- Ruff
- Gitleaks
- Pyright
- Test suites

---

# Suggested Installation

Runtime:

```bash
uv add "fastapi[standard]"
uv add pydantic-ai
uv add langfuse
uv add pydantic-settings
uv add httpx
```

Development:

```bash
uv add \
    pytest \
    pytest-asyncio \
    pyright \
    pydantic-evals \
    ruff \
    pre-commit \
    --dev
```

---

# Architecture Mapping

```text
FastAPI
    │
    ▼
PydanticAI
    │
    ▼
LLM Providers
(Claude / GPT / Gemini)
    │
    ▼
Langfuse
```

Supporting Infrastructure:

```text
pydantic-settings  → configuration
httpx              → API integrations
pytest             → testing
pytest-asyncio     → async testing
pyright            → type safety
pydantic-evals     → AI evaluations
ruff               → code quality
pre-commit         → commit-time protection
```

---

# Future Additions

Consider adding later when needed:

```bash
uv add litellm
```

For:

- Gateway architecture
- Multi-provider routing
- Failover
- Cost controls
- Enterprise AI patterns

```bash
uv add opentelemetry-api
uv add opentelemetry-sdk
```

For:

- Distributed tracing
- Service observability
- Production monitoring

```bash
uv add gitleaks --dev
```

(or via pre-commit hook)

For:

- Secret detection
- API key protection
- Compliance controls