#!/usr/bin/env bash
# Usage: bash bootstrap.sh [project-name]
set -euo pipefail

NAME="${1:-agentkit}"
mkdir "$NAME" && cd "$NAME"

uv init --bare --python 3.12
uv add "fastapi[standard]" "pydantic-ai-slim[anthropic,openai,mcp]" \
       langfuse pydantic-settings httpx pydantic-evals
uv add --dev pytest pytest-asyncio ruff pyright pre-commit

mkdir -p app/agents app/tools app/api tests evals
touch app/__init__.py app/agents/__init__.py app/tools/__init__.py app/api/__init__.py tests/__init__.py

# ---------------------------------------------------------------- config
cat > .env.example <<'EOF'
ANTHROPIC_API_KEY=
OPENAI_API_KEY=

# Role -> model (provider:model). Swap here, not in code.
DEFAULT_MODEL=anthropic:claude-haiku-5-5

# Optional: route everything through a LiteLLM proxy.
# When set, the role name (e.g. "default") is the model alias.
GATEWAY_URL=
GATEWAY_KEY=

# Per-run budget
MAX_REQUESTS=10
MAX_TOKENS=50000

# Tracing (optional)
LANGFUSE_PUBLIC_KEY=
LANGFUSE_SECRET_KEY=
LANGFUSE_HOST=https://cloud.langfuse.com
EOF
cp .env.example .env

cat > .gitignore <<'EOF'
.venv/
__pycache__/
.env
.pytest_cache/
.ruff_cache/
EOF

cat > litellm_config.yaml <<'EOF'
# Optional gateway: uv run litellm --config litellm_config.yaml --port 4000
# (requires: uv add "litellm[proxy]")
model_list:
  - model_name: default
    litellm_params: { model: anthropic/claude-haiku-5-5, api_key: os.environ/ANTHROPIC_API_KEY }
EOF

cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.6
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.0
    hooks:
      - id: gitleaks
EOF

cat >> pyproject.toml <<'EOF'

[tool.pytest.ini_options]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "function"
testpaths = ["tests"]

[tool.ruff]
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B"]

[tool.pyright]
include = ["app", "tests"]
typeCheckingMode = "standard"
EOF

# ---------------------------------------------------------------- app
cat > app/config.py <<'PY'
import os
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    anthropic_api_key: str | None = None
    openai_api_key: str | None = None

    default_model: str = "anthropic:claude-haiku-5-5"

    gateway_url: str | None = None
    gateway_key: str = "unused"

    max_requests: int = 10
    max_tokens: int = 50_000

    langfuse_public_key: str | None = None
    langfuse_secret_key: str | None = None
    langfuse_host: str = "https://cloud.langfuse.com"


@lru_cache
def get_settings() -> Settings:
    return Settings()


def export_env() -> None:
    """Provider SDKs read os.environ, not our Settings object."""
    s = get_settings()
    pairs = {
        "ANTHROPIC_API_KEY": s.anthropic_api_key,
        "OPENAI_API_KEY": s.openai_api_key,
        "LANGFUSE_PUBLIC_KEY": s.langfuse_public_key,
        "LANGFUSE_SECRET_KEY": s.langfuse_secret_key,
        "LANGFUSE_HOST": s.langfuse_host,
    }
    for k, v in pairs.items():
        if v:
            os.environ.setdefault(k, v)
PY

cat > app/models.py <<'PY'
"""Role -> model resolution. Agents never name a vendor.

To add a role: extend `Role`, add `<role>_model` to Settings and .env,
and add a matching alias in litellm_config.yaml if you use the gateway.
"""
from typing import Literal

from pydantic_ai.models import Model
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.openai import OpenAIProvider

from app.config import get_settings

Role = Literal["default"]


def build_model(role: Role = "default") -> Model | str:
    s = get_settings()
    if s.gateway_url:  # LiteLLM proxy: role name is the alias
        return OpenAIChatModel(
            role,
            provider=OpenAIProvider(base_url=s.gateway_url, api_key=s.gateway_key),
        )
    return getattr(s, f"{role}_model")
PY

cat > app/observability.py <<'PY'
from pydantic_ai import Agent

from app.config import export_env, get_settings


def setup() -> None:
    export_env()
    if get_settings().langfuse_public_key:
        from langfuse import get_client

        get_client()  # initializes the OTel exporter
        Agent.instrument_all()


def flush() -> None:
    if get_settings().langfuse_public_key:
        from langfuse import get_client

        get_client().flush()
PY

cat > app/schemas.py <<'PY'
from pydantic import BaseModel


class NewsItem(BaseModel):
    title: str
    url: str
    source: str | None = None
    published: str | None = None
PY

cat > app/tools/google_news.py <<'PY'
"""Google News search via the public RSS feed (no API key required)."""
import xml.etree.ElementTree as ET
from urllib.parse import quote_plus

import httpx

from app.schemas import NewsItem

FEED_URL = "https://news.google.com/rss/search?q={q}&hl=en-US&gl=US&ceid=US:en"
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; agentkit/0.1)"}


def parse_feed(xml: bytes) -> list[NewsItem]:
    root = ET.fromstring(xml)
    items: list[NewsItem] = []
    for node in root.findall("./channel/item"):
        source = node.find("source")
        items.append(
            NewsItem(
                title=(node.findtext("title") or "").strip(),
                url=(node.findtext("link") or "").strip(),
                source=source.text if source is not None else None,
                published=node.findtext("pubDate"),
            )
        )
    return items


async def search_google_news(query: str) -> NewsItem | None:
    """Return the first Google News result for `query`, or None."""
    url = FEED_URL.format(q=quote_plus(query))
    async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
        resp = await client.get(url, headers=HEADERS)
    resp.raise_for_status()
    items = parse_feed(resp.content)
    return items[0] if items else None
PY

cat > app/agents/news.py <<'PY'
"""Example agent: answers a question with the first Google News result.

Run without the server:  uv run python -m app.agents.news
"""
from pydantic_ai import Agent, ModelRetry
from pydantic_ai.usage import UsageLimits

from app.config import get_settings
from app.models import build_model
from app.schemas import NewsItem
from app.tools.google_news import search_google_news

DEFAULT_QUESTION = "what's the latest in fintech ai?"

news_agent = Agent(
    build_model("default"),
    output_type=NewsItem,
    instructions=(
        "Answer the question by calling google_news_search once with a concise "
        "search query, then return the first result exactly as the tool gave it. "
        "Never invent or alter fields."
    ),
    defer_model_check=True,
)


@news_agent.tool_plain
async def google_news_search(query: str) -> NewsItem:
    """Search Google News and return the first (top) result for the query."""
    item = await search_google_news(query)
    if item is None:
        raise ModelRetry("No results found. Try a broader query.")
    return item


async def ask_news(question: str = DEFAULT_QUESTION) -> NewsItem:
    s = get_settings()
    limits = UsageLimits(request_limit=s.max_requests, total_tokens_limit=s.max_tokens)
    result = await news_agent.run(question, usage_limits=limits)
    return result.output


if __name__ == "__main__":
    import asyncio

    from app.config import export_env

    export_env()
    print(asyncio.run(ask_news()).model_dump_json(indent=2))
PY

cat > app/api/routes.py <<'PY'
import httpx
from fastapi import APIRouter, HTTPException

from app.agents.news import DEFAULT_QUESTION, ask_news
from app.schemas import NewsItem

router = APIRouter()


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/news", response_model=NewsItem)
async def news(question: str = DEFAULT_QUESTION) -> NewsItem:
    try:
        return await ask_news(question)
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"Google News fetch failed: {e}") from e
PY

cat > app/main.py <<'PY'
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import observability
from app.api.routes import router


@asynccontextmanager
async def lifespan(_: FastAPI):
    observability.setup()
    yield
    observability.flush()


app = FastAPI(title="agentkit", lifespan=lifespan)
app.include_router(router)
PY

# ---------------------------------------------------------------- tests
cat > tests/conftest.py <<'PY'
import pytest
from pydantic_ai import models

models.ALLOW_MODEL_REQUESTS = False  # CI never hits a real model API


@pytest.fixture(autouse=True)
def _dummy_keys(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test")
PY

cat > tests/test_google_news.py <<'PY'
from app.tools.google_news import parse_feed

SAMPLE = b"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>fintech AI</title>
<item><title>AI reshapes lending - Example News</title>
<link>https://news.google.com/rss/articles/abc</link>
<pubDate>Mon, 09 Nov 2026 12:00:00 GMT</pubDate>
<source url="https://example.com">Example News</source></item>
<item><title>Second story - Other Wire</title>
<link>https://news.google.com/rss/articles/def</link>
<source url="https://other.example">Other Wire</source></item>
</channel></rss>"""


def test_parse_feed_returns_items_in_order():
    items = parse_feed(SAMPLE)
    assert [i.source for i in items] == ["Example News", "Other Wire"]
    assert items[0].title.startswith("AI reshapes lending")
    assert items[0].url.endswith("/abc")
    assert items[1].published is None
PY

cat > tests/test_agent.py <<'PY'
from pydantic_ai.models.test import TestModel

from app.agents.news import ask_news, news_agent
from app.schemas import NewsItem


async def test_agent_returns_news_item():
    with news_agent.override(model=TestModel(call_tools=[])):
        item = await ask_news()
    assert isinstance(item, NewsItem)


async def test_agent_calls_search_tool(monkeypatch):
    queries: list[str] = []

    async def fake_search(query: str) -> NewsItem:
        queries.append(query)
        return NewsItem(title="t", url="https://example.com")

    monkeypatch.setattr("app.agents.news.search_google_news", fake_search)
    with news_agent.override(model=TestModel()):
        await ask_news()
    assert len(queries) == 1
PY

cat > tests/test_api.py <<'PY'
import httpx
from pydantic_ai.models.test import TestModel

from app.agents.news import news_agent
from app.main import app


def _client() -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")


async def test_health():
    async with _client() as c:
        assert (await c.get("/health")).json() == {"status": "ok"}


async def test_news_endpoint():
    async with _client() as c:
        with news_agent.override(model=TestModel(call_tools=[])):
            r = await c.get("/news")
    assert r.status_code == 200
    assert {"title", "url"} <= r.json().keys()
PY

# ---------------------------------------------------------------- finish
git init -q
uv run pre-commit install || true
uv run pytest -q

echo
echo "Done. Next:"
echo "  1. Add ANTHROPIC_API_KEY to .env"
echo "  2. uv run python -m app.agents.news          # one-off run, no server"
echo "  3. uv run fastapi dev app/main.py            # then: curl localhost:8000/news"
