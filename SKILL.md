---
name: doc-freshness-analyzer
description: |
  GitHub リポジトリのドキュメント（README.md, docs/）とコードの実態を深層比較し、
  古い記述・不一致・誤情報を検出するスキル。
  
  **検出原則**: 疑わしきは報告（False Positiveは許容、False Negativeは回避）
  
  Use this skill when: 「ドキュメントが最新化されてるかチェック」「READMEの内容が正しいか確認」
  「ドキュメントとコードの整合性チェック」「古い記述がないか検証」と依頼された時。
  NOTE: リポジトリ単位で実行。全体チェックには時間がかかるため、対象リポジトリを指定して実行する。
allowed-tools: Bash, Read, Write, Glob, Grep, Task
---

# Document Freshness Analyzer

## Purpose

GitHub リポジトリのドキュメントを検証し、以下を検出する:
- コードの実態と一致しない記述
- 存在しないファイルパス・関数への参照
- 古いバージョン番号・依存関係
- 廃止されたコマンド・API
- 誤った設定例・実行手順

**品質原則:**
- **False Negative回避** = 疑わしきは報告
- **False Positive許容** = 過剰報告は手動で却下可能
- **検証不能 = potentialIssue** = 確認できない項目も報告

## Execution Model

**リポジトリ単位で実行**（全体チェックは非推奨）

```
User: portfolioリポジトリのドキュメント鮮度チェックして
User: ai-buzz-extractorのREADMEが正しいか確認
User: doc freshness check for neon-charts
```

## Analysis Flow

### Phase 1: Document Collection

対象ファイル:
- `README.md`（ルート）
- `docs/**/*.md`（ドキュメントフォルダ）
- `CONTRIBUTING.md`, `CHANGELOG.md`
- `*.md`（ルート直下のMarkdown）

### Phase 2: Code Reality Collection

収集対象:
1. **ファイル構造**: 実際に存在するファイル・ディレクトリ
2. **依存関係**: package.json, requirements.txt, Cargo.toml, go.mod
3. **設定ファイル**: .env.example, config files
4. **エントリポイント**: main files, scripts in package.json
5. **エクスポート**: 公開API、関数、クラス

### Phase 3: Claim Extraction & Verification

**Completion Criteria:**
- [ ] 15+クレーム抽出/ドキュメント
- [ ] 全クレームに検証結果あり
- [ ] エビデンス(file:line)を記載

**検証結果の種類:**
- `VERIFIED` - 確認済み
- `MISMATCH` - 不一致あり → issue
- `NOT_FOUND` - 見つからない → issue
- `UNVERIFIABLE` - 検証不能 → potentialIssue

### Phase 4: Report Generation

出力形式:
```markdown
# Document Freshness Report: {repo-name}

**Analyzed**: 2026-01-05 03:00 (JST)
**Documents checked**: 5 files
**Claims extracted**: 45
**Issues found**: 8
**Potential issues**: 3

## Critical Issues (Must Fix)

### 1. FILE_NOT_FOUND
- **Location**: README.md:45
- **Document says**: `src/utils/helper.js`
- **Reality**: File does not exist
- **Suggested fix**: Update to `src/lib/helpers.ts`

## Potential Issues (Manual Review)

### 1. UNVERIFIABLE
- **Claim**: "supports Node 18+"
- **Reason**: No engines field in package.json
- **Recommendation**: Add engines field or verify manually
```

## Detection Categories (20)

### Critical - Blocks Usage
| Category | Description |
|----------|-------------|
| FILE_NOT_FOUND | 参照ファイルが存在しない |
| FILE_MOVED | ファイルが移動されている |
| EXTENSION_MISMATCH | 拡張子が異なる (.js vs .ts) |
| CASE_MISMATCH | 大文字小文字の不一致 |
| COMMAND_INVALID | 実行できないコマンド |
| SCRIPT_MISSING | npm scriptsに存在しない |
| PACKAGE_MANAGER_WRONG | npm/bun/yarn/pnpmの不一致 |
| DEPENDENCY_MISSING | 記載依存関係が未インストール |

### Warning - Causes Errors
| Category | Description |
|----------|-------------|
| FUNCTION_RENAMED | 関数名が変更されている |
| FUNCTION_SIGNATURE_CHANGED | 関数の引数・戻り値が変更 |
| IMPORT_PATH_WRONG | importパスが解決不能 |
| EXPORT_MISSING | exportが存在しない |
| VERSION_MISMATCH | バージョン番号が古い |
| ENV_VAR_MISSING | 環境変数が.env.exampleにない |
| ENV_VAR_RENAMED | 環境変数名が変更されている |
| CONFIG_MISMATCH | 設定が実態と異なる |

### Info - Minor Issues
| Category | Description |
|----------|-------------|
| CONTRADICTION | ドキュメント内で矛盾 |
| INCOMPLETE | 必須情報が欠落 |
| UNVERIFIABLE | 検証不能（要手動確認） |
| DESCRIPTION_OUTDATED | 説明文が実態と乖離 |

## Script Files

- `scripts/collect-docs.ps1` - ドキュメント収集
- `scripts/collect-reality.ps1` - コード実態収集
- `scripts/collect-source.ps1` - ソースコード全量収集（export/import/route解析）
- `scripts/analyze-prompt.md` - Claude解析プロンプト
- `scripts/run-analysis.ps1` - 統合実行スクリプト

## Output Structure

```json
{
  "issues": [...],           // 確実な問題（high/medium confidence）
  "potentialIssues": [...],  // 要手動確認（low confidence / UNVERIFIABLE）
  "verified": [...],         // 確認済みクレーム
  "missingDocs": [...]       // 追加すべきドキュメント
}
```

**`potentialIssues`の意義:**
- 検証不能な項目を別セクションに分離
- ユーザーが手動で確認・却下可能
- False Positiveによるノイズを軽減

## Integration

### With repo-freshness-checker
- `repo-freshness-checker`: 更新日ベースの簡易チェック（全リポジトリ対象）
- `doc-freshness-analyzer`: 内容ベースの深層チェック（リポジトリ単位）

### Recommended Workflow
1. 毎日: `repo-freshness-checker` で更新状況を把握
2. 週1/リリース前: `doc-freshness-analyzer` で重要リポジトリを深層検証
