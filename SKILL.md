---
name: doc-freshness-analyzer
description: |
  GitHub リポジトリのドキュメント（README.md, docs/）とコードの実態を深層比較し、
  古い記述・不一致・誤情報を**99%以上の精度**で検出するスキル。
  
  **検出精度目標**: 99%+ (False Negative = ツール失敗)
  **検出原則**: 疑わしきは報告（False Positiveは許容、False Negativeは禁止）
  
  Use this skill when: 「ドキュメントが最新化されてるかチェック」「READMEの内容が正しいか確認」
  「ドキュメントとコードの整合性チェック」「古い記述がないか検証」と依頼された時。
  NOTE: リポジトリ単位で実行。全体チェックには時間がかかるため、対象リポジトリを指定して実行する。
allowed-tools: Bash, Read, Write, Glob, Grep, Task
---

# Document Freshness Analyzer

## Purpose & Quality Target

GitHub リポジトリのドキュメントを**99%以上の精度**で検証する。

**検出目標:**
- コードの実態と一致しない記述 → **100%検出**
- 存在しないファイルパス・関数への参照 → **100%検出**
- 古いバージョン番号・依存関係 → **99%検出**
- 廃止されたコマンド・API → **99%検出**
- 誤った設定例・実行手順 → **99%検出**

**品質原則:**
- **False Negative = ツール失敗** (見逃しは許されない)
- **False Positive = 許容** (疑わしきは報告)
- **検証不能 = Warning報告** (確認できない = 潜在的問題)

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

## Detection Categories (25カテゴリ)

### Critical (P0/P1) - 即時修正必須
| Category | Description | Detection Priority |
|----------|-------------|-------------------|
| FILE_NOT_FOUND | 参照ファイルが存在しない | 100% |
| FILE_MOVED | ファイルが移動されている | 100% |
| EXTENSION_MISMATCH | 拡張子が異なる (.js vs .ts) | 100% |
| CASE_MISMATCH | 大文字小文字の不一致 | 100% |
| COMMAND_INVALID | 実行できないコマンド | 100% |
| SCRIPT_MISSING | npm scriptsに存在しない | 100% |
| PACKAGE_MANAGER_WRONG | npm/bun/yarn/pnpmの不一致 | 100% |
| DEPENDENCY_MISSING | 記載依存関係が未インストール | 100% |
| FUNCTION_RENAMED | 関数名が変更されている | 99% |
| FUNCTION_SIGNATURE_CHANGED | 関数の引数・戻り値が変更 | 99% |
| IMPORT_PATH_WRONG | importパスが解決不能 | 99% |
| EXPORT_MISSING | exportが存在しない | 99% |
| EXAMPLE_WONT_RUN | コード例が動作しない | 99% |
| SECURITY_RISK | セキュリティ設定の誤り | 100% |

### Warning (P2) - 要レビュー
| Category | Description | Detection Priority |
|----------|-------------|-------------------|
| VERSION_MISMATCH | バージョン番号が古い | 99% |
| DEPENDENCY_UNUSED | 記載依存関係が使われていない | 95% |
| ENV_VAR_MISSING | 環境変数が.env.exampleにない | 99% |
| ENV_VAR_RENAMED | 環境変数名が変更されている | 99% |
| API_CHANGED | APIエンドポイントが変更 | 99% |
| ENDPOINT_MISSING | エンドポイントが存在しない | 99% |
| CONFIG_KEY_RENAMED | 設定キー名が変更 | 95% |
| CONTRADICTION | ドキュメント内で矛盾 | 95% |
| INCOMPLETE | 必須情報が欠落 | 90% |
| UNVERIFIABLE | 検証不能（潜在的問題） | 100% |

### Info (P3) - 軽微
| Category | Description | Detection Priority |
|----------|-------------|-------------------|
| DESCRIPTION_OUTDATED | 説明文が実態と乖離 | 85% |
| DEAD_LINK | 外部リンク切れ | 80% |

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
- `scripts/collect-source.ps1` - ソースコード全量収集（export/import/route解析）
- `scripts/analyze-prompt.md` - Claude解析プロンプト（99%精度設計）
- `scripts/run-analysis.ps1` - 統合実行スクリプト

## Quality Assurance Checklist

分析完了時、以下を確認すること:

```
□ クレーム抽出数: 20件以上/ドキュメント
□ 検証カバレッジ: 95%以上
□ ファイルパス: 全件検証済み
□ コマンド: 全件検証済み
□ 依存関係: 全件検証済み
□ 関数/クラス: exports listと照合済み
□ 検証不能項目: Warning報告済み
□ 修正提案: コピペ可能な形式
```

**チェックリスト未完了 = 分析失敗**

## False Negative Prevention Protocol

**絶対原則: 疑わしきは報告**

1. **検証できない** → Warning「UNVERIFIABLE」として報告
2. **部分一致** → Mismatchとして報告（完全一致でなければ問題）
3. **類似ファイル発見** → FILE_MOVED候補として報告
4. **確信が持てない** → 低confidence で報告

**見逃し(False Negative)はツールの存在意義を否定する失敗である**
