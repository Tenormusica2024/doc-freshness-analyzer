# doc-freshness-analyzer

Deep analysis tool that compares documentation (README.md, docs/) with actual code implementation to detect outdated, incorrect, or missing information.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[English](README.md) | [Japanese](README.ja.md)

## Problem

Documentation often drifts from code reality:
- File paths that no longer exist
- Outdated dependency versions
- Renamed functions or changed signatures
- Removed features still documented
- Missing documentation for new features

## Solution

This tool performs **deep verification** by:
1. Extracting all technical claims from documentation
2. Comparing against actual code structure (files, exports, imports, routes)
3. Reporting mismatches with suggested fixes

## Features

- **21 Detection Categories**: FILE_NOT_FOUND, VERSION_MISMATCH, IMPORT_PATH_WRONG, etc.
- **SmartMode**: 77% token reduction by focusing on "active" files only
- **Incremental Analysis**: 80% time reduction for large repositories
- **GitHub Actions Integration**: Automated PR checks
- **Auto-fix PR Creation**: Generate fix PRs automatically

## Quick Start

```powershell
# Analyze a GitHub repository
./scripts/run-analysis.ps1 -Target owner/repo

# Analyze with DeepMode (all files)
./scripts/run-analysis.ps1 -Target owner/repo -DeepMode

# Incremental analysis (cached)
./scripts/run-analysis.ps1 -Target owner/repo -Incremental

# Verify external URLs
./scripts/run-analysis.ps1 -Target owner/repo -VerifyUrls
```

## Detection Categories

### Critical (Blocks Usage)
| Category | Description |
|----------|-------------|
| FILE_NOT_FOUND | Referenced file doesn't exist |
| COMMAND_INVALID | Command cannot be executed |
| DEPENDENCY_MISSING | Listed dependency not installed |
| SCRIPT_MISSING | npm script doesn't exist |

### Warning (Causes Errors)
| Category | Description |
|----------|-------------|
| FUNCTION_RENAMED | Function name changed |
| IMPORT_PATH_WRONG | Import path cannot resolve |
| VERSION_MISMATCH | Version number outdated |
| ENV_VAR_MISSING | Environment variable not in .env.example |

### Info (Minor Issues)
| Category | Description |
|----------|-------------|
| CONTRADICTION | Inconsistency within documentation |
| DEAD_LINK | External URL returns 404 |
| UNVERIFIABLE | Cannot verify (needs manual check) |

## SmartMode vs DeepMode

| Mode | Description | Use Case |
|------|-------------|----------|
| **SmartMode** (default) | Only fetches content for "active" files (importance score >= 30) | Regular analysis, token-efficient |
| **DeepMode** | Fetches all source file content | Major refactoring, comprehensive audit |

### Importance Scoring
| Condition | Score |
|-----------|-------|
| Entry point (index.js, main.py) | +50 |
| Referenced in package.json scripts | +40 |
| Imported by other files | +30/file (max +60) |
| Referenced in CI/CD workflows | +35 |
| Modified within 30 days | +20 |
| Config file (.json, .yaml) | +25 |
| API route | +30 |

## Output Format

```json
{
  "issues": [
    {
      "severity": "critical",
      "category": "FILE_NOT_FOUND",
      "location": { "file": "README.md", "lineNumber": 45 },
      "documentSays": "src/utils/helper.js",
      "realityIs": "File does not exist",
      "suggestedFix": "Update to src/lib/helpers.ts"
    }
  ],
  "potentialIssues": [...],
  "verified": [...],
  "summary": {
    "freshnessScore": 85,
    "totalIssues": 3
  }
}
```

## GitHub Actions Integration

```yaml
name: Doc Freshness Check
on:
  pull_request:
    paths: ['**.md', 'package.json']

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Analysis
        run: pwsh ./scripts/run-analysis.ps1 -Target ${{ github.repository }}
```

## Comparison with Similar Tools

| Tool | Focus | doc-freshness-analyzer Advantage |
|------|-------|----------------------------------|
| readme-inspector | README existence & quality score | Deep content verification |
| rdme (ReadMe CLI) | API docs sync | Code structure comparison |
| Dosu | AI doc generation | 21 detection categories, SmartMode |
| markdownlint | Markdown syntax | Semantic accuracy checking |

## Requirements

- PowerShell 7+
- GitHub CLI (`gh`) authenticated
- Claude Code CLI (for analysis phase)

## Design Philosophy

This tool is designed for **personal use with Claude Code CLI** (subscription-based), not Claude API (pay-per-use).

**Why no API integration?**
- Zero additional cost for Claude Pro/Max subscribers
- No API key management required
- Interactive analysis with human oversight
- Cost-effective for individual developers

**Trade-offs:**
- Requires local PC to be running
- Cannot run fully automated in CI/CD (data collection only)
- Manual trigger required for analysis phase

If significant demand emerges, API integration may be considered in future versions.

## License

MIT

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.
