# doc-freshness-analyzer

ドキュメント（README.md, docs/）とコードの実態を深層比較し、古い記述・不一致・誤情報を検出するツール。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[English](README.md) | [日本語](README.ja.md)

## 概要

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

## Detection Categories (21)

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
| DEAD_LINK | 外部URLが404/無効 |

## Script Files

- `scripts/collect-docs.ps1` - ドキュメント収集
- `scripts/collect-reality.ps1` - コード実態収集
- `scripts/collect-source.ps1` - ソースコード収集（SmartMode/DeepMode対応、重要度スコアリング）
- `scripts/analyze-prompt.md` - Claude解析プロンプト
- `scripts/run-analysis.ps1` - 統合実行スクリプト
- `scripts/create-fix-pr.ps1` - 自動修正PR作成
- `scripts/cache-manager.ps1` - インクリメンタル解析用キャッシュ管理
- `scripts/verify-urls.ps1` - 外部URL生存確認（HTTP HEAD）
- `scripts/test-collect-docs.ps1` - ドキュメント収集テスト
- `scripts/test-debug.ps1` - デバッグ用テスト
- `.github/workflows/doc-freshness.yml` - GitHub Actions CI/CD
- `schema/analysis-output.schema.json` - 出力JSON Schema

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

### GitHub Actions Integration

PR作成時に自動チェック:
```yaml
on:
  pull_request:
    paths: ['**.md', 'package.json']
```

手動実行:
```bash
gh workflow run doc-freshness.yml -f target_repo=owner/repo
```

### Auto-fix PR Creation

検出した問題を自動修正:
```powershell
./scripts/create-fix-pr.ps1 -Target owner/repo -AnalysisResult ./result.json
```

生成されるPR:
- タイトル: `docs: fix N documentation issues`
- ブランチ: `docs/freshness-fix-YYYYMMDD`
- 各issueのsuggestedFixを適用

### Incremental Analysis Mode

変更ファイルのみ再解析（大規模リポジトリで80%時間削減）:
```powershell
./scripts/run-analysis.ps1 -Target owner/repo -Incremental
```

動作:
1. `~/.doc-freshness-cache/`（ホームディレクトリ直下）に前回結果をキャッシュ
2. git diff（ローカル）またはGitHub API compare（リモート）で変更検出
3. 変更なし→キャッシュ結果を即座に返却
4. 変更あり→変更ファイル情報を付与して再解析

キャッシュ無効化:
```powershell
./scripts/run-analysis.ps1 -Target owner/repo -InvalidateCache
```

### URL Verification

外部URLの生存確認（DEAD_LINK検出強化）:
```powershell
./scripts/run-analysis.ps1 -Target owner/repo -VerifyUrls
```

スタンドアロン実行:
```powershell
./scripts/verify-urls.ps1 -InputFile ./source-data.json
```

機能:
- HTTP HEADで生存確認（タイムアウト10秒）
- Rate limiting対応（500ms間隔）
- リダイレクト検出と修正提案
- localhost/example.com等の除外

### Smart Mode vs Deep Mode

デフォルトはSmartMode（トークン節約）:
```powershell
./scripts/run-analysis.ps1 -Target owner/repo
```

全ソースファイルの内容を取得（大規模解析用）:
```powershell
./scripts/run-analysis.ps1 -Target owner/repo -DeepMode
```

**SmartMode（デフォルト）:**
- 「現役ファイル」のみ内容取得
- 「古い/未使用ファイル」はメタデータのみ
- トークン使用量を大幅削減

**DeepMode:**
- 全ソースファイルの内容を取得
- 大規模リファクタリング時に推奨

**現役ファイル判定基準（重要度スコア30以上）:**
| 判定条件 | スコア |
|----------|--------|
| エントリポイント（index.js, main.py等） | +50 |
| package.json scriptsから参照 | +40 |
| 他ファイルからimportされている | +30/import（最大+60） |
| CI/CDワークフローから参照 | +35 |
| 直近30日以内に変更 | +20 |
| 設定ファイル（.json, .yaml等） | +25 |
| APIルート（pages/api/, routes/等） | +30 |

**出力に含まれる情報:**
```json
{
  "activeFiles": ["src/index.ts", ...],
  "inactiveFiles": [
    {"path": "old-script.js", "importance": 0, "reason": "Low importance"}
  ],
  "summary": {
    "mode": "smart",
    "activeFileCount": 15,
    "inactiveFileCount": 23
  }
}
```

## Implementation Notes

### Performance Optimizations (v1.1)
- **正規表現エスケープの事前計算**: `$escapedPath`, `$escapedBasename`を関数先頭で1回だけ計算し、ループ内で再利用
- **ArrayList使用**: 配列結合（`+=`）の代わりに`[void]$list.Add()`でO(1)追加
- **パス結合統一**: `[System.IO.Path]::Combine()`に統一し、エッジケース（空文字列）対応

### Code Quality
- **ImportedByフィルタリング**: null/空文字列を除外 (`Where-Object { $_ -and $_.Trim() }`)
- **エラーメッセージ形式**: `[Category] context: message`で統一
- **PowerShell変数展開**: コロン含むパスは`${var}`形式で安全にエスケープ

### Test Results
```
Mode: smart | Active: 6 | Inactive: 32
Source files with content: 6 (840 lines)
Token reduction: ~77%
```

## 設計思想

このツールは **Claude Code CLI（サブスクリプション）での個人利用** を前提に設計されています。Claude API（従量課金）は使用しません。

**API連携しない理由:**
- Claude Pro/Maxユーザーは追加コストなし
- APIキー管理が不要
- 人間の監視下でのインタラクティブな分析
- 個人開発者にとってコスト効率が良い

**トレードオフ:**
- ローカルPCが起動している必要がある
- CI/CDで完全自動化はできない（データ収集のみ）
- 分析フェーズは手動トリガーが必要

将来的に需要が出れば、API連携を検討する可能性があります。
