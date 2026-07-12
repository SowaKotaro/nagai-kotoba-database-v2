# 実装 Issue リスト(単語収集・解析アプリ)

段階的な実装計画と改善バックログ。**1 Issue = 1 ブランチ = 1 PR** を原則とする。

- アプリ全体像・実装状況・ローカル環境: [`docs/overview.md`](overview.md)
- データモデル・横断方針(照合順序・公開方針など): [`CLAUDE.md`](../CLAUDE.md) / [`docs/schema.sql`](schema.sql)
- グロース戦略と現状評価: [`docs/growth-strategy.md`](growth-strategy.md)
- 収録基準の正: [`docs/annotation-guidelines.md`](annotation-guidelines.md)

## 記述フォーマット(統一)

各 Issue は次の形式で記述する。完了した Issue は詳細を落として「完了アーカイブ」節へ要約して移す(経緯の詳細は git 履歴で参照できる)。

```
## Issue N: タイトル
- 種別: feature / improvement / bug / ops
- 状態: 未着手 / 対応中 / 保留(理由) / 完了(PR #n)
- 優先度: P0〜P2 ／ Impact: High/Med/Low ／ Effort: High/Med/Low
- 依存: Issue n / なし
- 背景・現状: (1〜3行)
- 内容: (チェックリスト)
- 期待効果: (1〜2行)
```

- 種別 `ops` = コード変更を伴わない(または僅かな)運用・インフラ作業。
- 優先度の目安: P0 = 公開(インデックス解禁)の前提条件、P1 = 解禁前後に済ませたい土台、P2 = データ量・トラフィックの成長に合わせて。

---

# 未完了イシュー(優先度順)

## Issue 42: プライバシーポリシー・外部送信情報の公表ページ(/privacy)
- 種別: feature
- 状態: 未着手
- 優先度: P0 ／ Impact: High ／ Effort: Low〜Med
- 依存: なし
- 背景・現状: GA4(gtag.js)で利用者情報を Google へ外部送信しているのに、公表ページが無い。改正電気通信事業法の外部送信規律の観点で公開前に必須。E-E-A-T(サイトの信頼性)の面でも欠けている。
- 内容:
  - [ ] `PagesController#privacy`(`GET /privacy`、`allow_unauthenticated_access`)を追加(About と同じ作法)
  - [ ] 記載事項: 外部送信の内容(GA4 — 送信先事業者・送信される情報・利用目的)/Cookie の利用/アクセスログの取り扱い/お問い合わせ先(About と共有)
  - [ ] フッターに恒久リンク。About・llms.txt からも参照
  - [ ] GA4 無効環境(`GA4_MEASUREMENT_ID` 未設定)でも矛盾しない文言にする
- 期待効果: 法的リスクの回避。公開(インデックス解禁)の前提条件を満たす。

## Issue 43: インデックス解禁スイッチ(全ページ noindex の環境変数切替)
- 種別: improvement
- 状態: 未着手
- 優先度: P0 ／ Impact: High ／ Effort: Low
- 依存: なし
- 背景・現状: 確定事項「注釈済み 300〜500 語まで全ページ noindex、解禁時に外す」の実装が無い。現状の noindex はファセット絞り込みページと `/search` のみで、解禁前に jp ドメインで公開するとインデックスを制御できない。
- 内容:
  - [ ] レイアウトの meta robots を環境変数(例 `INDEXING_ENABLED`)で切替。**未設定 = 全ページ `noindex`** とし、解禁時に本番へ設定する
  - [ ] ファセットの noindex 判定(Issue 17)との共存(全体 noindex が優先)
  - [ ] 環境変数の有無それぞれでメタタグ出力を検証する結合テスト
  - [ ] 解禁チェックリストを docs 化: 環境変数設定 → Search Console 所有権確認 → sitemap 送信 → インデックス状況の観測開始(Issue 44 と連動)
- 期待効果: 解禁タイミングを運用で確実に制御できる。準備中のページが中途半端にインデックスされる事故を防ぐ。

## Issue 34: 統計ページ(収録データの分布・集計)
- 種別: feature
- 状態: 未着手(着手前に相談。Phase 1 から)
- 優先度: P1 ／ Impact: Med ／ Effort: Med(Phase 1 のみ。Phase 2 は別 PR)
- 依存: Issue 26(キャッシュ基盤。実装済み)
- 背景・現状: 収録データの統計(ジャンル別語数・読み文字数の分布・語種別・品詞別・先頭文字別など)を見せるページが無い。「全体像が見える」ページは回遊・被リンク獲得(「◯◯のデータによると〜」と引用される)に効く。毎回全レコードを走査する実装はスケールしないため、集計テーブルの要否が論点だった。
- 内容: **2 段階で実装する。統計テーブルは先行して作らない**(統計は元データから常に再計算できる導出データのため)。
  - [ ] **Phase 1(初版・当面はこれで十分)**: `StatsController#index`(`/stats`、`allow_unauthenticated_access`)でオンライン集計(`WordSense.published` を `group(...).count` 群。インデックス済みカラムのみ使用)+ `Rails.cache.fetch`(TTL 数時間、またはアノテーション保存時にキー削除)。1 万語規模なら GROUP BY は数十 ms 以下
  - [ ] **収録数の推移**(月別の登録数・累計)も Phase 1 に含める(「生きているサイト」の可視化。[`growth-strategy.md`](growth-strategy.md) §1)
  - [ ] グラフ表現は `docs/design.md` 準拠(墨・朱のみ。チャートライブラリは入れず CSS/インライン SVG の棒グラフ程度)
  - [ ] **Phase 2(数十万レコード級になったら)**: 集計テーブル(例 `stats_snapshots`)+ 冪等な再集計タスク `stats:rebuild`(`backfill:reading_metrics` と同じ作法)。「正 = フル再計算タスク、登録時フックはキャッシュ削除に留める」構成
- 期待効果: 回遊・再訪の増加、統計データとしての被リンク・引用の獲得、収録規模の可視化による信頼性提示。
- 補足: データが数百語を超えてから公開する。

## Issue 44: 計測運用の立ち上げ(KPI 定義・Search Console 登録)
- 種別: ops
- 状態: 未着手
- 優先度: P1 ／ Impact: High ／ Effort: Low
- 依存: Issue 43(解禁チェックリストと連動)
- 背景・現状: GA4 の実装・検証タグの ENV 対応(Issue 19)は済んでいるが、本番の測定 ID 設定・所有権確認・sitemap 送信・KPI 定義が未実施。計測は「増え始めてから」では過去データが取れないため、解禁前に完了させる。
- 内容:
  - [ ] 本番に `GA4_MEASUREMENT_ID` を設定し計測開始(解禁前からベースラインを取る)
  - [ ] Search Console・Bing Webmaster Tools の所有権確認(検証タグの ENV は実装済み)と sitemap 送信(解禁時)
  - [ ] KPI ツリーを [`growth-strategy.md`](growth-strategy.md) §3 に追記(PV・AU に加え、新規/再訪比率・流入チャネル別・検索/ファセット利用率・1訪問あたり閲覧語数)
  - [ ] GA4 カスタムイベント(検索実行・ファセットクリック・シェアクリック)の要否を検討(必要なら小さな別 PR)
- 期待効果: 流入クエリ・インデックス状況の観測に基づく改善サイクルの確立。

## Issue 45: 監視・エラー通知(外形監視 + Rails 例外通知)
- 種別: ops
- 状態: 未着手
- 優先度: P1 ／ Impact: Med ／ Effort: Low〜Med
- 依存: なし
- 背景・現状: 死活監視・エラー通知が無く、本番障害・エラー多発に気づく手段がゼロ。人気が出る(=見てくれる人が増える)前に整備する。2026-07-12 の技術監査でも High(全障害の検知が利用者の指摘待ち)と再確認。
- 内容:
  - [ ] 外形監視: 無料の監視サービス(UptimeRobot 等)で `/` と `/up`(ヘルスチェック)を監視し、ダウン時にメール通知
  - [ ] エラー通知: Rails の error reporter(`Rails.error.subscribe`)でメール通知、または gem 導入を比較検討(**gem 追加は相談の上**)
  - [ ] nginx / Puma のログローテーション設定の確認
- 期待効果: 障害・エラーの検知が「ユーザーに言われて気づく」から「先に気づいて直す」になる。

## Issue 46: DB バックアップの自動化(日次 mysqldump + 世代管理)
- 種別: ops
- 状態: 未着手
- 優先度: P1 ／ Impact: High ／ Effort: Low
- 依存: なし
- 背景・現状: 本番 DB のバックアップが手動(`~/db_backups` に随時取得)。アノテーション済みデータは復元不能な労働の成果であり、消失リスクが最大の単一障害点。2026-07-12 の技術監査でも **Critical(最重要)** と再確認。
- 内容:
  - [ ] 本番サーバの cron で日次 `mysqldump`(deploy ユーザー、gzip 圧縮、`~/db_backups`)
  - [ ] 世代管理(例: 日次 30 世代 + 月次数世代を保持、古いものは削除)
  - [ ] リストア手順を docs 化(既存のバックアップ・リセット運用の知見を反映)
  - [ ] 可能ならサーバ外への退避(別ホスト・オブジェクトストレージ等)を検討
- 期待効果: データ消失リスクの解消。**インフラ変更のため実施前に内容を説明する**(CLAUDE.md 方針)。

## Issue 49: deploy:seed × マスタリネームの重複再発防止
- 種別: bug
- 状態: 未着手(**対策方式は着手前に相談**)
- 優先度: P1 ／ Impact: High ／ Effort: Med
- 依存: なし
- 背景・現状: 2026-07-12 の技術監査より(High)。マスタ seed は `find_or_create_by!(name:)` で名前照合するため、`/admin/tags` で seed 由来のマスタをリネーム/統合すると、`deploy:seed` 自動実行(`config/deploy.rb`)により**次回デプロイで旧名のマスタが復活**し重複が生じる。2026-07-10 の db:reset で一掃済みだが、再発を防ぐコード上の手当てが無く構造的に再発する。
- 内容:
  - [ ] 対策方式の決定: (a) seed に旧名→新名のリネーム追従マップを持たせる / (b) seed 由来マスタの一覧を管理画面に表示しリネームを禁止・警告する / (c) deploy:seed の投入対象を admins のみに絞る — のいずれか(組み合わせ可)
  - [ ] seed コメントの「冪等なので安全」の記述を、名前変更時の挙動を踏まえた正確な内容に修正
  - [ ] リネーム→デプロイ相当(seed 再実行)で重複が生じないことのテスト
- 期待効果: マスタ重複の再発防止。タグ統括管理(/admin/tags)と seed 運用の安全な共存。

## Issue 51: backfill タスクが last_char を再計算しない
- 種別: bug
- 状態: 未着手
- 優先度: P1 ／ Impact: Med ／ Effort: Low
- 依存: なし
- 背景・現状: 2026-07-12 の技術監査より(Medium)。派生カラム(`char_type_pattern`/`rhythm_pattern`/`mora_count`/`vowel_pattern`/`last_char`)は `before_validation` 依存のため、`update_all` や直接 SQL で reading/surface を直すと古くなる。修復用の `backfill:reading_metrics` タスク(`lib/tasks/backfill.rake`)が **`last_char` だけ再計算していない**ため、修復してもなお不整合が残る。
- 内容:
  - [ ] `backfill:reading_metrics` に `last_char`(`LastChar`)の再計算を追加
  - [ ] 派生値の全件検証タスク(現在値と再計算値の diff を報告する読み取り専用タスク)を追加
  - [ ] backfill 後に last_char が正しく埋まることのテスト
- 期待効果: 派生カラム修復手段の完全化。検索結果への古い値の静かな混入を検出可能に。

## Issue 29: OGP 画像の動的生成(単語ごと)
- 種別: feature
- 状態: 未着手(収録が数百語を超え、共有が発生し始めてから)
- 優先度: P2 ／ Impact: Med ／ Effort: High
- 依存: なし(静的 og:image は Issue 14 で導入済み)
- 背景・現状: og:image は全ページ共通の静的 1 枚のみで、単語ごとの画像ではない。「言葉そのものが主役」のデザインは OGP 画像との相性が良く、共有時の CTR を大きく左右する。
- 内容:
  - [ ] 単語詳細ごとに 1200×630 の画像を生成: 紙×墨×朱デザインの SVG テンプレート(巨大明朝で表層形 + 読み + サイト名)を ERB で組み、libvips(`image_processing` gem 追加)か rsvg-convert で PNG 化
  - [ ] 生成タイミングはアノテーション保存時 or 初回リクエスト時 + ファイルキャッシュ
  - [ ] フォント埋め込みの検証
- 期待効果: X・Slack・チャット AI での共有時の視認性・CTR 向上。

## Issue 31: Web フォントのセルフホスト化
- 種別: improvement
- 状態: 未着手(woff2 サブセット取得が必要)
- 優先度: P2 ／ Impact: Med ／ Effort: Med
- 依存: なし
- 背景・現状: Shippori Mincho を Google Fonts から読んでいる(レイアウトで 2 オリジンへ preconnect)。外部 DNS/TLS 往復が LCP に乗り、可用性も外部依存。
- 内容:
  - [ ] Google Fonts の CSS と同じ unicode-range 分割の woff2 サブセット(weights 500/600)を取得して `app/assets` に配置
  - [ ] `@font-face` を自前 CSS 化(`font-display: swap` 維持)、preconnect 2 行を削除
  - [ ] 「web フォントは明朝 1 本」の方針は維持
- 期待効果: LCP 改善(外部往復の排除)、CSP を将来有効化する際の単純化。

## Issue 33: 用例(usage example)フィールドの追加
- 種別: feature
- 状態: 未着手(**着手前に運用方針を相談**)
- 優先度: P2 ／ Impact: Med ／ Effort: High
- 依存: なし
- 背景・現状: 語義に用例・出典を持つ場所が無い。定義 + 用例が揃うと辞書ページとしての情報量・独自性が大きく上がるが、現スキーマでは表現できない。データ入力の運用コストが掛かるのが論点。
- 内容:
  - [ ] `word_sense_examples` テーブル(`word_sense_id`, `text`, `source`(任意))を追加
  - [ ] アノテーション・コンソール(`admin/annotations`)に入力欄、`words#show` に表示
  - [ ] JSON-LD(構造化データ)にも反映
- 期待効果: ページの独自性・情報量の向上(他辞書との差別化)、LLM が用例ごと引用できる構造。

## Issue 47: 「今日の一語」X 自動投稿
- 種別: feature
- 状態: 未着手(**着手前に相談**。X API の制約調査から)
- 優先度: P2 ／ Impact: Med ／ Effort: Med
- 依存: なし(「今日の一語」の選定ロジックは実装済み)
- 背景・現状: 公開側にアカウント機能を作らない方針のため、再訪のきっかけが少ない。日替わりの「今日の一語」はトップに実装済みだが、サイト外へ届ける手段が無い。
- 内容:
  - [ ] X API の無料枠・投稿制限・審査要件を調査(制約次第で方式・頻度を決める)
  - [ ] 投稿文フォーマット設計(表層形 + リード文 + 単語詳細 URL。動的 OGP 画像(Issue 29)があれば効果増)
  - [ ] 実装方式の選定: サーバ cron + rake タスク(冪等・失敗時は翌日に自然回復)を第一候補に
  - [ ] 認証情報は credentials / 環境変数で管理
- 期待効果: SNS 経由の定常的な流入と再訪のきっかけ。フォローによる実質的な「購読」導線。

## Issue 48: fragment cache の残り(browse・genres)
- 種別: improvement
- 状態: 未着手
- 優先度: P2 ／ Impact: Low ／ Effort: Low
- 依存: Issue 26(実装済み)
- 背景・現状: Issue 26 で HTTP キャッシュ・`Rails.cache`(ホーム統計)は導入済みだが、fragment cache は未導入。`/browse`(五十音表・文字数リンクの件数集計)と `/genres`(ツリー + 語義数)は毎回 GROUP BY を発行している(`browse_controller.rb` に「Issue 26 で導入予定」コメントが残る)。
- 内容:
  - [ ] `/browse` の件数集計と `/genres` のツリー描画を fragment cache または `Rails.cache.fetch` 化
  - [ ] キー設計: TTL(数時間)またはアノテーション保存時の無効化(ホーム統計 `home/stats` と方針を揃える)
  - [ ] コード内の古い「Issue 26 で導入予定」コメントを整理
- 期待効果: TTFB 短縮とクローラ流量への耐性。1 万語規模でも集計ページが軽いまま保てる。

## Issue 52: 一括登録の類似チェック(Levenshtein 総当たり)の負荷軽減
- 種別: improvement
- 状態: 未着手(データ量の成長に合わせて)
- 優先度: P2 ／ Impact: Med ／ Effort: Med
- 依存: なし
- 背景・現状: 2026-07-12 の技術監査より(Medium)。一括登録 step3 の重複チェック(`bulk_word_registration.rb`)が DB の全 (reading, surface) を pluck し、貼り付けた各行と純 Ruby の Levenshtein 距離を同期計算する。長さ差の枝刈りはあるが、100行×1万語規模では単一 Puma worker(スレッド5)を数秒占有し、公開側レスポンスも巻き添えになる。
- 内容:
  - [ ] `reading_length`(インデックス済み)による長さ帯での DB 側事前絞り込み
  - [ ] 効果が不足する場合は先頭文字での絞り込み・trigram 等の前段フィルタを検討
  - [ ] 1万語規模の擬似データでの処理時間計測(before/after)
- 期待効果: 一括登録時の公開側への影響排除。データ量が増えても登録フローが快適なまま保てる。

## Issue 53: 公開検索の負荷対策(レートリミット・COUNT/LIKE)
- 種別: improvement
- 状態: 未着手(トラフィックの成長に合わせて)
- 優先度: P2 ／ Impact: Med ／ Effort: Med
- 依存: なし
- 背景・現状: 2026-07-12 の技術監査より(Medium)。キーワード検索・韻/母音検索は中間一致 LIKE でインデックスが効かず、1ページ表示ごとに COUNT + 本体の2クエリが走る。レートリミットはログイン(`sessions#create`)のみで、公開の検索/JSON をクローラに叩かれ続けると単一 DB サーバに負荷が直撃する。
- 内容:
  - [ ] 検索・JSON エンドポイントへのレートリミット(Rails 8 標準 `rate_limit` か rack-attack。**gem 追加は相談の上**)
  - [ ] 検索結果 COUNT のキャッシュ検討
  - [ ] 規模拡大時: FULLTEXT インデックス(ngram parser)への移行検討
- 期待効果: クローラ・悪意あるアクセスへの耐性。単一サーバ構成の延命。

## Issue 54: Atom フィードのジャンル祖先 N+1 解消
- 種別: bug
- 状態: 未着手
- 優先度: P2 ／ Impact: Low ／ Effort: Low
- 依存: なし
- 背景・現状: 2026-07-12 の技術監査より(Medium)。`words#feed` は `includes(word_senses: :genre)` だが、リード文生成(`words_helper.rb` の `self_and_ancestors`)で genre の parent→parent を遅延ロードするため、最大 20語×2階層 ≒ 40 クエリの N+1。`words#show` は `genre: { parent: :parent }` を preload しており対照的。
- 内容:
  - [ ] feed の preload を `words#show` と同じ深さ(`genre: { parent: :parent }`)に揃える
  - [ ] フィードへの HTTP キャッシュ(`fresh_when` / `expires_in`)の追加検討
- 期待効果: フィード取得のクエリ数削減(約40→数クエリ)。クローラ・リーダーの定期アクセスに強くなる。

## Issue 55: config.load_defaults を 8.1 へ引き上げ
- 種別: improvement
- 状態: 未着手
- 優先度: P2 ／ Impact: Med ／ Effort: Med
- 依存: なし
- 背景・現状: 2026-07-12 の技術監査より(Medium)。`config/application.rb` が `config.load_defaults 7.1` のまま Rails 8.1 を運用しており、7.2/8.0/8.1 の新既定(セキュリティ・パフォーマンス関連)が適用されていない。
- 内容:
  - [ ] `new_framework_defaults` の手順で差分となる既定値を洗い出し、段階的に有効化
  - [ ] 各既定値の影響(特に Cookie・キャッシュフォーマット・SQL 生成まわり)をテストで確認
  - [ ] 最終的に `config.load_defaults 8.1` へ引き上げ
- 期待効果: フレームワーク推奨状態への追従。将来の Rails アップグレードコストの低減。

## Issue 56: 技術監査 Low 指摘の小粒対応まとめ
- 種別: improvement
- 状態: 未着手(個別に着手する際は項目ごとに分割してよい)
- 優先度: P2 ／ Impact: Low ／ Effort: Low〜Med
- 依存: なし
- 背景・現状: 2026-07-12 の技術監査の Low 指摘のうち、未 Issue 化のものをまとめて記録する(実施は任意・随時)。
- 内容:
  - [ ] `genre_must_be_small`(小分類のみ許可)の DB 側担保が無い — 将来の直接更新で中・大分類が混入し得る(現状の経路は安全)
  - [ ] `words.surface` の UNIQUE が prefix(191) — 先頭191文字が同一の長文語は DB エラーになる(現実的に稀。長文語を扱うならハッシュカラム + UNIQUE)
  - [ ] キャッシュ・`rate_limit` が `:memory_store`(プロセス内) — `WEB_CONCURRENCY` を上げると worker 間で分裂する。Solid Cache 移行時に要注意
  - [ ] `rails/all` ロード — ActionCable/ActionMailbox/ActiveStorage/ActionMailer は未使用。個別 require 化でメモリ・攻撃面を削減
  - [ ] mecab 依存テストが CI で skip — 読み自動取得の回帰が CI で検出されない(フォールバック設計自体は堅牢)
  - [ ] CSP 未設定 — GA(インライン script)・Google Fonts があるため、フォント自前化(Issue 31)後に導入検討
- 期待効果: 技術的負債の可視化。将来の構成変更(worker 増設・キャッシュ移行)時の事故防止。

## Issue 27: config.hosts 設定と canonical ホストへの 301 統一
- 種別: improvement
- 状態: 保留(**com → jp 移行タイミングに合わせて実施**。インフラ変更)
- 優先度: P1(移行時) ／ Impact: Med ／ Effort: Low(URL 単位マッピングが必要な場合は Med)
- 依存: なし
- 背景・現状: 2026-07-12 の技術監査でも High と再確認(Host ヘッダ攻撃への保護欠如 + `assume_ssl` が nginx 設定への暗黙依存)。`config/environments/production.rb` の `config.hosts` がコメントアウトのままで Host ヘッダ保護が無効。www あり/なし・IP 直アクセスの正規化も無い。本番ドメインは `nagai-kotoba-database.jp` で確定。現在は旧システムが `nagai-kotoba-database.com` で稼働中で、データ移行完了後に nginx で com → jp のリダイレクトを設定予定。
- 内容:
  - [ ] `config.hosts` に `nagai-kotoba-database.jp` を設定(`/up` は `host_authorization` の exclude で除外)
  - [ ] nginx 側で www・IP 直アクセスを canonical ホストへ 301
  - [ ] `config.assume_ssl = true` の有効化も確認
  - [ ] **com → jp の移行**: 旧 .com がインデックス済みなら、ドメイン単位の一括リダイレクトではなく可能な範囲で URL 単位の 301 マッピング(旧単語ページ → 対応する新 `/words/:id`)+ Search Console「アドレス変更」ツールで通知(評価・被リンクの引き継ぎ)。未インデックスならドメイン単位 301 のみで可
- 期待効果: 重複ホストの排除(canonical と併せて評価の集約)、旧ドメインからの評価引き継ぎ、セキュリティ強化。**インフラ設定変更なので影響範囲を説明の上で実施**。

---

# 完了アーカイブ

## 基盤実装(Issue 1〜12、`docs/schema.sql` ベースの段階実装)

- **Issue 1: 設計ドキュメント整備とスキーマ方針確定** [improvement] — 完了。`docs/schema.sql` 取り込み・本 Issue リスト・CLAUDE.md 作成。
- **Issue 2: ジャンル(genres)マスタ** [feature] — 完了。3階層・自己参照(`parent_id`)、`utf8mb4_0900_ai_ci` 統一(既存 `admins`/`sessions` も変換)、ローカルは docker compose の MySQL 8.4(ホスト3307)。
- **Issue 3: 単純マスタ3種** [feature] — 完了。entity_types / parts_of_speech / linguistic_features。`PartOfSpeech` の inflection 追加。
- **Issue 4: words テーブルと char_type_pattern** [feature] — 完了。値オブジェクト `CharTypePattern` + `before_validation`。変換仕様は [`docs/char_type_pattern.md`](char_type_pattern.md)(`ー`はカタカナ扱い・`々`は漢字扱い)。
- **Issue 5: word_senses テーブル** [feature] — 完了。STORED 生成カラム(`reading_length`/`first_char`/`last_char`)、`genre_id` は level3 のみ許可、`rhythm_pattern` はヘボン式・長音は母音展開([`docs/rhythm_pattern.md`](rhythm_pattern.md))。
- **Issue 6: word_sense_features(語義×特徴の多対多)** [feature] — 完了。特徴は該当部分ごと(`target`/`target_reading`。後に `target_start` 追加で同一文字列の複数出現に対応)。
- **Issue 7: 管理者用 CRUD** [feature] — 完了。`Admin::` 名前空間・1画面フル入れ子フォーム・ジャンルの依存ドロップダウン。
- **Issue 8: 公開閲覧(一覧・詳細)** [feature] — 完了。`allow_unauthenticated_access`、gem なしの軽量ページネーション。
- **Issue 9: 検索・絞り込み** [feature] — 完了。クエリオブジェクト `WordSenseSearch`、公開 `/search`、キーワード検索 `q`。
- **Issue 10: マスタのインライン追加** [feature] — クローズ。Issue 12 のアノテーション・コンソールで実質実装(その場追加)。対象だった `/admin/words` フォームは現運用(一括登録 + コンソール)の主動線でないため対応しない。
- **Issue 11: 拡張データ(読み指標・語種・別表記)** [feature] — 完了。`mora_count`/`vowel_pattern`、語種マスタ `word_origins`(多対多)、別表記 `word_sense_variants`、バックフィル `backfill:reading_metrics`。
- **Issue 12: 高速アノテーション・コンソール** [feature] — 完了。1語集中キュー型(`annotated_at`)、チップ UI・段階ジャンル・範囲タップ・マスタその場追加・語義複製。

## SEO・LLMO 改善(Issue 13〜34、2026-07-06 のリポジトリ全体分析より)

検索エンジン・AI 検索経由の流入最大化の観点で分析したバックログ。未公開のうちに技術 SEO の土台を整備した。

- **Issue 13: favicon / apple-touch-icon 差し替え** [bug] — 完了(PR #34)。0 バイトの空ファイルを `icon.svg` から生成した実体に差し替え。
- **Issue 14: メタ情報の動的生成** [improvement] — 完了(PR #36)。description・OGP(静的 og:image 含む)・twitter:card・canonical をヘルパー + `content_for` で。
- **Issue 15: sitemap.xml + robots.txt** [feature] — 完了(PR #37)。動的 sitemap(注釈済み全語 + 静的ページ、1日キャッシュ)、robots に Sitemap 行と `/admin` 等の Disallow。
- **Issue 16: 構造化データ JSON-LD** [feature] — 完了(PR #40)。`DefinedTerm`/`DefinedTermSet`・`BreadcrumbList`・`WebSite`+`SearchAction`。
- **Issue 17: ファセットのインデックス方針** [improvement] — 完了(PR #38)。単一条件は動的 title でインデックス許可、複数条件・`q`・page 2 以降は noindex、`/search` は noindex。
- **Issue 18: 単語詳細の自動リード文** [improvement] — 完了(PR #35)。構造化データから決定的に組み立てる定義文。meta description・JSON-LD・Atom に流用。
- **Issue 19: GA4 + Search Console** [feature] — 完了(PR #39)。Turbo 対応の page_view 送信、検証タグは ENV 対応。本番の測定 ID 設定・所有権確認は **Issue 44 に引き継ぎ**。
- **Issue 20: About ページ** [feature] — 完了(PR #41)。目的・収録基準(読み10文字以上)・精査方針・ライセンス(CC BY 4.0)・連絡先。
- **Issue 21: /genres ハブページ** [feature] — 完了(PR #43)。ジャンル木 + 語義数 + ファセットへのリンク。
- **Issue 22: 50音・文字数の索引ページ /browse** [feature] — 完了(PR #45)。五十音表(朱ヒート)+ 読み文字数別リンク。
- **Issue 23: 関連語セクション** [feature] — 完了(PR #44)。同ジャンル・同文字数・同先頭文字の単語間内部リンク。
- **Issue 24: llms.txt** [feature] — 完了(PR #42)。サイト概要・主要 URL・API 案内・ライセンス(About と文言共有)。
- **Issue 25: 公開 JSON API** [feature] — 完了(PR #46)。`words#index/#show` の `.json`(jbuilder、CC BY 表記つき)。
- **Issue 26: HTTP/fragment キャッシュ** [improvement] — 完了(PR #47)。`fresh_when`/ETag・ホーム統計の `Rails.cache`・`touch` 連鎖。fragment cache の残タスクは **Issue 48 に引き継ぎ**。
- **Issue 28: 新着単語 Atom フィード** [feature] — 完了(PR #48)。注釈済み新着 20 件 + autodiscovery。
- **Issue 30: シェア導線** [feature] — 完了(PR #49)。X 共有リンク + URL コピー(インライン SVG)。
- **Issue 32: エラーページの日本語化・ブランド化** [improvement] — 完了(PR #50)。404/422/500 を自前デザインで。

(Issue 27・29・31・33・34 は未完了節を参照)

## 管理者機能の改善(Issue 35〜41、2026-07-07 のオーナーフィードバックより)

一括登録は高評価で現状維持。アノテーション以降に「まとめて処理」「機械の下書き」「Claude Code 連携」が無いのがボトルネック(未注釈約 6,000 語)という分析に基づく改善群。全体は PR #54〜#57 ほかで実装。

- **Issue 35: 管理画面の共通ナビゲーション** [improvement] — 完了。ダッシュボード/登録/アノテーション/一覧/公開サイトへの常設サブナビ。
- **Issue 36: 単語管理一覧の刷新と編集画面のコンソール統合** [improvement] — 完了。一覧に読み・注釈状態・検索・絞り込み・コンソール直リンク。編集画面は廃止しコンソールに表層形編集を追加。
- **Issue 37: 共通属性の一括アノテーション** [feature] — 完了。一覧からジャンル・品詞・エンティティ・語種・意味テンプレを選択語へ一括適用(複数語義の語はスキップ)。コンソールに引き継ぎトグル。
- **Issue 38: Claude Code 連携アノテーション** [feature] — 完了(本命)。調査用データ書き出し → `word-annotation-research` スキル → `annotation_proposals` へ取り込み → コンソールで承認(`annotated_at` を立てるのは人間のみ)。
- **Issue 39: アノテーションヘルパー** [feature] — 完了。[`docs/annotation-guidelines.md`](annotation-guidelines.md)(収録4原則・立項スコア)、特徴の用語解説(glossary YAML)、提案パネルの立項スコア表示。
- **Issue 40: 管理UIシステムテストの flake 解消** [improvement] — 完了。原因は WSL/Chrome 150 のネイティブクリック不達 + confirm 自動クローズ。`click_accepting_confirm` ヘルパー(confirm スタブ + JS クリック)で安定化。CI で再発したら再起票。ローカル実行手順は `LD_LIBRARY_PATH` + `CHROME_BIN` 方式(詳細は git 履歴)。
- **Issue 41: AnnotationProposal の複数語義対応** [feature] — 完了。payload に `senses` 配列を持ち、同一表記の同音異義語(例: ピーターパンシンドローム)をコンソールで語義ごとに反映可能に。
- **アノテーション FB 修正(番号なし)** — 完了。`target_start`(特徴の出現位置)/注釈済みの語でも提案表示/保存後スクロール/調査スキルの2周調査化。

## 技術監査対応(Issue 49〜56、2026-07-12 の監査より)

- **Issue 50: 管理者セッションの有効期限** [improvement] — 完了(PR #71)。永続 Cookie(約20年)を2週間の `expires` に変更。サーバ側も `updated_at` ベースのスライディング失効(`Session::LIFETIME`)を導入し、期限切れはアクセス時に破棄・ログイン時に掃除。DB 書き込みと Set-Cookie は1時間間隔に間引き。

---

# 確定事項(オーナー回答の記録)

## 2026-07-06(SEO・LLMO)

1. **本番ドメイン**: `nagai-kotoba-database.jp` で確定。旧システムが `nagai-kotoba-database.com` で稼働中。データ移行完了後に com → jp リダイレクト(詳細は Issue 27)。
2. **アナリティクス**: GA4 で確定(Turbo 対応の page_view 送信が必須。実装済み)。
3. **収録基準**: **読み 10 文字以上**で確定(正: [`docs/annotation-guidelines.md`](annotation-guidelines.md))。
4. **ライセンス**: 単語データは **CC BY 4.0(クレジット表記 = サイト名 + URL)**。MIT はコード向けのためデータには不適合(コードを OSS 公開する場合はそちらに MIT)。About・llms.txt・JSON API に明示済み。
5. **インデックス解禁**: **注釈済み 300〜500 語を目安に解禁**。それまで全ページ noindex(環境変数切替。実装は Issue 43)。解禁時に sitemap を Search Console へ送信。

## 2026-07-07(管理者機能)

6. **一括登録(3ステップ)は現状維持**。量と質を両立できており不満なし。
7. **編集画面はコンソールへ吸収して廃止**(Issue 36)。表層形の編集はコンソール、削除ボタンは一覧に残す。
8. **Claude Code の提案は「DB に下書き保存 → コンソールで承認」方式**(Issue 38)。直接 DB 書き込み(承認レス)は採らない。
9. **一括適用の「注釈済み」フラグはチェックボックスで選択式**(既定 OFF、Issue 37)。
