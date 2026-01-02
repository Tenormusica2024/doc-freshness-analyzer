---
name: doc-freshness-analyzer
description: |
  GitHub リポジトリのドキュメント（README.md, docs/）とコードの実態を深層比較し、
  古い記述・不一致・誤情報を細部まで検出するスキル。
  Use this skill when: 「ドキュメントが最新化されてるかチェック」「READMEの内容が正しいか確認」
  「ドキュメントとコードの整合性チェック」「古い記述がないか検証」と依頼された時。
  NOTE: リポジトリ単位で実行。全体チェックには時間がかかるため、対象リポジトリを指定して実行する。
allowed-tools: Bash, Read, Write, Glob, Grep, Task
---

# Document Freshness Analyzer

## Purpose

GitHub リポジトリのドキュメントを**細部まで精査**し、以下を検出する:
- コードの実態と一致しない記述
- 存在しないファイルパス・関数への参照
- 古いバージョン番号・依存関係
- 廃止されたコマンド・API
- 誤った設定例・実行手順

## Execution Model

**リポジトリ単位で実行**（全体チェックは非推奨）

```
User: portfolioリポジトリのドキュメント鮮度チェックして
User: ai-buzz-extractorのREADMEが正しいか確認
User: doc freshness check for neon-charts
```

## Analysis Flow

### Phase 1: Document Collection (30秒)

対象ファイル:
- `README.md`（ルート）
- `docs/**/*.md`（ドキュメントフォルダ）
- `CONTRIBUTING.md`, `CHANGELOG.md`
- `*.md`（ルート直下のMarkdown）

収集方法:
```bash
# ローカルリポジトリの場合
find /path/to/repo -name "*.md" -type f

# GitHub APIの場合
gh api repos/{owner}/{repo}/contents/README.md
gh api repos/{owner}/{repo}/git/trees/main?recursive=1
```

### Phase 2: Code Reality Collection (30秒)

収集対象:
1. **ファイル構造**: 実際に存在するファイル・ディレクトリ
2. **依存関係**: package.json, requirements.txt, Cargo.toml, go.mod
3. **設定ファイル**: .env.example, config files
4. **エントリポイント**: main files, scripts in package.json
5. **エクスポート**: 公開API、関数、クラス

### Phase 3: Deep Analysis (3-8分)

Claude が以下を比較検証:

#### 3.1 ファイルパス検証
```
Doc: "Edit src/utils/helper.js"
Reality: src/utils/helper.js が存在しない → ❌ STALE
```

#### 3.2 コマンド検証
```
Doc: "Run npm run dev"
Reality: package.json に "dev" script がない → ❌ STALE
Reality: bun.lockb 存在 → "bun run dev" が正しい可能性
```

#### 3.3 バージョン検証
```
Doc: "Requires Node.js 16+"
Reality: package.json engines: ">=18" → ❌ OUTDATED
```

#### 3.4 依存関係検証
```
Doc: "Uses axios for HTTP requests"
Reality: package.json に axios がない、fetch 使用 → ❌ STALE
```

#### 3.5 機能・API検証
```
Doc: "Call getUserById(id) to fetch user"
Reality: 関数名が getUser(id) に変更されている → ❌ STALE
```

#### 3.6 設定例検証
```
Doc: "Set API_KEY in .env"
Reality: .env.example に API_KEY がない、OPENAI_API_KEY に変更 → ❌ STALE
```

### Phase 4: Report Generation

出力形式:
```markdown
# Document Freshness Report: {repo-name}

**Analyzed**: 2026-01-02 20:15 (JST)
**Documents checked**: 5 files
**Issues found**: 12

## Critical Issues (Must Fix)

### 1. Incorrect file path
- **Location**: README.md, Line 45
- **Document says**: `src/utils/helper.js`
- **Reality**: File does not exist. Similar: `src/lib/helpers.ts`
- **Suggested fix**: Update path to `src/lib/helpers.ts`

### 2. Outdated command
- **Location**: README.md, Line 23
- **Document says**: `npm run dev`
- **Reality**: No npm lockfile, bun.lockb present
- **Suggested fix**: Change to `bun run dev`

## Warnings (Should Review)

### 3. Version mismatch
- **Location**: README.md, Line 12
- **Document says**: "Node.js 16+"
- **Reality**: package.json requires ">=18"
- **Suggested fix**: Update to "Node.js 18+"

## Info (Minor)

### 4. Potentially outdated description
- **Location**: README.md, Line 5
- **Document says**: "Simple todo app"
- **Reality**: Feature set has expanded significantly
- **Suggested fix**: Consider updating description
```

## Invocation Examples

```
# 特定リポジトリのチェック
User: portfolioリポジトリのドキュメント鮮度チェックして

# ローカルディレクトリ指定
User: C:\Users\Tenormusica\projects\my-app のREADMEが正しいか確認

# GitHub URL指定
User: https://github.com/tenormusica2024/neon-charts のドキュメント検証
```

## Detection Categories

| Category | Severity | Example |
|----------|----------|---------|
| FILE_NOT_FOUND | Critical | 参照ファイルが存在しない |
| COMMAND_INVALID | Critical | 実行できないコマンド |
| API_CHANGED | Critical | 関数名・引数が変更されている |
| VERSION_MISMATCH | Warning | バージョン番号が古い |
| DEPENDENCY_REMOVED | Warning | 使われていない依存関係への言及 |
| CONFIG_CHANGED | Warning | 設定項目名が変更されている |
| DESCRIPTION_OUTDATED | Info | 説明文が実態と乖離 |
| LINK_BROKEN | Info | 外部リンクが切れている |

## Integration

### With repo-freshness-checker
- `repo-freshness-checker`: 更新日ベースの簡易チェック（全リポジトリ対象）
- `doc-freshness-analyzer`: 内容ベースの深層チェック（リポジトリ単位）

### Recommended Workflow
1. 毎日: `repo-freshness-checker` で更新状況を把握
2. 週1/リリース前: `doc-freshness-analyzer` で重要リポジトリを深層検証

## Script Files

- `scripts/collect-docs.ps1` - ドキュメント収集
- `scripts/collect-reality.ps1` - コード実態収集
- `scripts/analyze-prompt.md` - Claude解析プロンプト
- `scripts/run-analysis.ps1` - 統合実行スクリプト
