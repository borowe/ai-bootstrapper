---

# Repository Secret Protection Strategy (4 Layers)

## Overview

No single control is sufficient to prevent secrets from entering source control.

A mature implementation uses multiple independent layers:

```text
Developer
    │
    ▼
Layer 1: Local Pre-Commit Scan
    │
    ▼
Layer 2: Automated Developer Setup
    │
    ▼
Layer 3: CI/CD Secret Scanning
    │
    ▼
Layer 4: Repository Security Platform
```

This creates defense in depth.

Even if one control is bypassed, another should prevent the secret from reaching production repositories.

---

# Layer 1 - Local Pre-Commit Secret Scanning

## Goal

Detect secrets before a commit is created.

Examples:

- OpenAI API keys
- Anthropic API keys
- AWS credentials
- Azure credentials
- JWTs
- Database passwords
- Generic high-entropy secrets

## Recommended Tool

Gitleaks

Repository:

```text
https://github.com/gitleaks/gitleaks
```

## Example .pre-commit-config.yaml

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.0
    hooks:
      - id: gitleaks

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.6
    hooks:
      - id: ruff-check
      - id: ruff-format
```

## Install

```bash
uv add pre-commit --dev
```

Install hooks:

```bash
pre-commit install
```

## What Happens

Developer attempts:

```bash
git commit -m "feature"
```

Workflow:

```text
Git Commit
    │
    ▼
Gitleaks Scan
    │
    ▼
No Secrets Found
    │
    ▼
Commit Allowed
```

If a secret is detected:

```text
Commit Failed
Potential Secret Detected
```

---

# Layer 2 - Automated Developer Setup

## Goal

Ensure every developer installs required hooks.

Important:

```text
Git does NOT clone .git/hooks.
```

You cannot force hook installation simply because someone cloned a repository.

Instead, automate installation through onboarding scripts.

## Example setup.sh

```bash
#!/bin/bash

uv sync

pre-commit install
```

Developer onboarding:

```bash
git clone <repo>

cd repo

./scripts/setup.sh
```

## Recommended Documentation

Place onboarding instructions in:

```text
README.md
```

Example:

```markdown
# First-Time Setup

uv sync

pre-commit install
```

---

# Layer 3 - CI/CD Enforcement (Required)

## Goal

Protect against:

```bash
git commit --no-verify
```

or developers that never installed hooks.

Local checks improve developer experience.

CI provides actual enforcement.

## GitHub Actions Example

```yaml
name: Secret Scan

on:
  pull_request:
  push:

jobs:
  detect-secrets:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install Gitleaks
        run: |
          curl -sSfL https://raw.githubusercontent.com/gitleaks/gitleaks/master/install.sh | sh

      - name: Run Secret Scan
        run: |
          gitleaks detect --source . --verbose
```

## Workflow

```text
Developer Pushes Code
         │
         ▼
 CI Secret Scan
         │
         ▼
 Secret Found?
     /       \
   Yes       No
    │         │
    ▼         ▼
 Build     Continue
 Failed
```

Recommended policy:

```text
Fail the PR when secrets are detected.
```

---

# Layer 4 - Repository Security Platform

## Goal

Provide independent repository-level monitoring.

Examples:

- GitHub Secret Scanning
- GitHub Advanced Security
- Azure DevOps Secret Scanning
- Enterprise DLP Platforms

These solutions continuously scan repositories for leaked credentials.

## Why This Matters

Eventually someone will:

```bash
git commit --no-verify
```

or

```text
Disable Hooks
```

or

```text
Push from another machine
```

Repository-level scanning provides a final safety net.

---

# Recommended Enterprise Architecture

```text
Developer Workstation
        │
        ▼
Pre-Commit Hook
(Gitleaks)
        │
        ▼
Git Commit
        │
        ▼
Git Push
        │
        ▼
CI/CD Secret Scan
(Gitleaks)
        │
        ▼
Pull Request Approval
        │
        ▼
Merge
        │
        ▼
Repository Secret Scanning
(GitHub/Azure Security)
```

Each layer is intentionally independent.

The goal is not to trust a single control.

The goal is to ensure that failure of one control does not result in credentials reaching source control.

---

# Additional Recommended Pre-Commit Hooks

As projects mature, consider adding additional quality gates.

Example:

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.0
    hooks:
      - id: gitleaks

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.6
    hooks:
      - id: ruff-check
      - id: ruff-format
```

Potential future additions:

```text
Pyright
Unit Tests
Security Scanning
Dependency Vulnerability Scanning
```

Common pattern:

```text
Commit
 │
 ├── Secret Scan
 ├── Ruff Lint
 ├── Ruff Format
 ├── Type Check
 └── Unit Tests
```

The earlier issues are caught, the cheaper they are to fix.