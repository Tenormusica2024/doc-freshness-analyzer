# Roadmap - doc-freshness-analyzer

## Competitive Analysis Summary

比較対象ツール:
- **Swimm** (商用) - コード連動ドキュメント、自動更新、IDE統合
- **Semcheck** (OSS/Go) - LLMで仕様vs実装検証
- **Doc Detective** (OSS/Node.js) - ドキュメントをE2Eテスト実行
- **markdownlint** (OSS) - Markdown構文チェック

### Current Strengths
- 依存関係の深い解析（package.json, requirements.txt）
- export/import/route解析（他ツールにない機能）
- potentialIssues分離によるノイズ軽減
- 対象リポジトリへの変更不要

### Current Gaps (Resolved)
- ~~CI/CD統合なし~~ → GitHub Actions対応済み
- ~~自動修正機能なし~~ → create-fix-pr.ps1で対応済み
- ~~外部リンク検証なし~~ → DEAD_LINK検証対応済み

---

## Improvement Priorities

### Priority 1: HIGH (Next Sprint) ✅

#### 1.1 GitHub Actions Integration ✅
- [x] `.github/workflows/doc-freshness.yml` 作成
- [x] 手動トリガー（workflow_dispatch）対応
- [x] PR時の自動チェック対応
- [x] 結果をPRコメントとして投稿

**Expected Impact**: CI/CDパイプラインに組み込み可能になり、継続的なドキュメント品質管理を実現

#### 1.2 JSON Output Standardization ✅
- [x] JSON Schemaの定義
- [x] `--output json` オプション追加（-JsonOnlyで対応）
- [x] 他ツールとの連携用フォーマット

**Expected Impact**: 他ツールやダッシュボードとの統合が容易に

---

### Priority 2: MEDIUM (Backlog)

#### 2.1 SuggestedFix Precision
- [ ] ファイルパス修正の自動生成精度向上
- [ ] 類似ファイル検出時の具体的パス提案
- [ ] コピペ可能な修正コードブロック生成

#### 2.2 External Link Verification (DEAD_LINK) ✅
- [x] URL抽出機能（collect-source.ps1）
- [x] DEAD_LINK検証指示（analyze-prompt.md）
- [x] suggestedFix対応
- [x] HTTP HEADによる実際の存在チェック（verify-urls.ps1）
- [x] Rate limiting対応（500ms間隔）

#### 2.3 Incremental Analysis Mode ✅
- [x] キャッシュ機構（cache-manager.ps1）
- [x] git diff連携（ローカル/GitHub API）
- [x] run-analysis.ps1 -Incremental オプション
- [x] キャッシュ無効化機能

**Expected Impact**: 大規模リポジトリで80%の解析時間削減

---

### Priority 3: LOW (Future) ✅

#### 3.1 Auto-fix PR Creation ✅
- [x] 検出した問題の自動修正
- [x] 修正PRの自動作成（create-fix-pr.ps1）
- [x] レビュー待ちPRとしてプッシュ
- [x] DryRunモード対応

#### 3.2 Integration Enhancements
- [ ] Slack通知
- [ ] 定期実行スケジュール
- [ ] ダッシュボードUI

---

### Priority 4: PLANNED (Future Enhancements)

#### 4.1 Auto-Update Documentation (Planned)
- [ ] ドキュメント変更の自動検出・提案
- [ ] コード変更時に該当ドキュメントを自動更新
- [ ] Dosu/Swimm風のリアルタイム同期機能
- [ ] Git hooks連携（pre-commit, post-merge）

**Expected Impact**: ドキュメントのdriftを未然に防止、メンテナンスコスト大幅削減

#### 4.2 Multi-Platform Support
- [ ] Node.js版（npm package）
- [ ] Python版（pip package）
- [ ] Docker image

#### 4.3 AI-Powered Suggestions
- [ ] 修正内容の自動生成（Claude API連携強化）
- [ ] ドキュメント品質スコアの詳細分析
- [ ] 類似パターン検出による一括修正提案

---

## Not Planned

- ~~VSCode拡張~~ - 工数対効果が低い
- ~~E2Eテスト実行~~ - Doc Detectiveの領域

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | 2026-01-06 | SmartMode実装（77%トークン削減）、コードレビュー修正、英語ドキュメント追加 |
| 0.4.0 | 2026-01-05 | Incremental Analysis Mode, HTTP HEAD URL Verification |
| 0.3.0 | 2026-01-05 | GitHub Actions CI/CD, JSON Schema, DEAD_LINK検証, 自動修正PR作成 |
| 0.2.0 | 2026-01-05 | プロンプト設計改善、potentialIssues分離 |
| 0.1.0 | 2026-01-04 | 初期リリース |
