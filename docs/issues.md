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

## Issue 69: 既定キューを提案付き優先に
- 種別: improvement
- 状態: 未着手
- 優先度: P2 ／ Impact: Low〜Med ／ Effort: Low
- 依存: なし
- 背景・現状: 既定キュー = 全 pending、提案付きは `?proposed=1` 別動線。提案の無い語に着地すると surface+reading だけで手調査になり激遅。
- 内容:
  - [ ] 既定順を「提案あり→先頭」に寄せる、またはコンソール入口を提案付き優先に
  - [ ] 提案の無い語しか残っていないときの導線(書き出しへ誘導)
- 期待効果: 人間が常に下調べ済みの語に着地する(スキルを事実上の正面玄関に)。

## Issue 70: アノテーション体験の小粒改善まとめ
- 種別: improvement
- 状態: 未着手(項目ごとに分割してよい)
- 優先度: P2 ／ Impact: Low ／ Effort: Low〜Med
- 依存: なし
- 背景・現状: 2026-07-16 のアノテーション UX 調査で挙がった、単独 Issue にするほどでない磨き込みをまとめて記録する(実施は任意・随時)。
- 内容:
  - [ ] 新設マスタ作成時に「似ているマスタ」を提示し分類ドリフト(近似重複マスタ)を防ぐ
  - [ ] デスクトップ・キーボードパワーモード(数字キーでチップ選択・Ctrl/Cmd+Enter でどこからでも保存・次語プリフェッチ)。タブレット第一の思想と両立する補助として
  - [ ] 長い読みの範囲タップ改善(セル拡大・「語全体を選択」ショートカット)
  - [ ] 書き出し/取り込みのファイル入出力(DL/UP)・書き出し画面に実行プロンプト同梱でコピペ往復を短縮
  - [ ] 未提案語の「調べる」導線(web 検索リンク or 提案生成への誘導)
- 期待効果: 1操作あたりの摩擦低減の積み上げ。

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
- 補足: データが数百語を超えてから公開する。エンタメ寄りの看板ビジュアル「五十音円環」は Issue 62 として分離(本 Issue の Phase 1 には含めない)。

## Issue 44: 計測運用の立ち上げ(KPI 定義・Search Console 登録)
- 種別: ops
- 状態: 一部完了(KPI 定義・手順の文書化は済み。残りは本番での運用作業)
- 優先度: P1 ／ Impact: High ／ Effort: Low
- 依存: Issue 43(解禁チェックリストと連動。実装済み)
- 背景・現状: GA4 の実装・検証タグの ENV 対応(Issue 19)は済んでいるが、本番の測定 ID 設定・所有権確認・sitemap 送信が未実施。計測は「増え始めてから」では過去データが取れないため、解禁前に完了させる。
- 内容:
  - [ ] 本番に `GA4_MEASUREMENT_ID` を設定し計測開始(解禁前からベースラインを取る。手順は [`launch-checklist.md`](launch-checklist.md) §1)
  - [ ] Search Console・Bing Webmaster Tools の所有権確認(検証タグの ENV は実装済み)と sitemap 送信(解禁時。同 §1・§3)
  - [x] KPI ツリーを [`growth-strategy.md`](growth-strategy.md) §3 に追記(北極星 = 週あたりの「語を見た訪問」数。量・質・資産の3系統)
  - [x] GA4 カスタムイベントの要否を検討 → **当面入れない**(page_view の URL パラメータで代替できる。解禁後に不足が明確になったら小さな別 PR。growth-strategy.md §3 に記録)
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

## Issue 57: ことばの散歩(軸つきランダム遷移)
- 種別: feature
- 状態: 未着手
- 優先度: P2 ／ Impact: Med ／ Effort: Low
- 依存: なし
- 背景・現状: 2026-07-15 のエンタメ機能アイデア出しより(採用)。公開側の回遊導線は関連語セクション(Issue 23)のみで、「次の一語」へ偶然の出会いで飛ぶ仕掛けが無い。単純なランダム遷移は1回で飽きるため、軸を選んで飛ぶ形にする。
- 内容:
  - [ ] 単語詳細に「散歩」導線: しりとりで次へ(`last_char`→`first_char`)・同じジャンルへ・同じ頭文字へ・同じモーラ数へ 等の軸別ランダム遷移(各1クエリ、インデックス済みカラムのみ使用)
  - [ ] 一覧向けのランダム複数件表示も同じ仕組みで
  - [ ] しりとりで「ん」終わりの語に着いたら「しりとり敗北」演出(朱の一枚画面)
  - [ ] 検索0件の空振り画面にも「代わりにこの語はどうか」でランダム一語を提示
- 期待効果: 回遊の背骨。滞在時間・語詳細の閲覧数の底上げ。

## Issue 58: 単語詳細の「鑑定書」とンホホ変換一行
- 種別: feature
- 状態: 未着手
- 優先度: P2 ／ Impact: Med ／ Effort: Low
- 依存: なし
- 背景・現状: 2026-07-15 のアイデア出しより(条件付き採用)。ガチャ的な演出は雰囲気に合わないため不採用とし、希少性は博物館の標本ラベルの文法で「文言」として静かに刻む。イヤンホホ変換(「ホン」→「ンホホ」の SNS 発の言葉遊び)は汎用変換ページにせず詳細ページの一行に留める(確定事項 11・13)。
- 内容:
  - [ ] 鑑定文: 読みの長さの上位パーセンタイル(`COUNT(*) WHERE reading_length >= ?` の1クエリ)・多義語・特徴数などを標本ラベル風の文で表示
  - [ ] 演出は朱の一文字印(「稀」等のインライン SVG 印章)程度に抑える(エフェクト・レアリティ表記は入れない)
  - [ ] ンホホ変換: 値オブジェクト1個(「ホン」→「ンホホ」+ 語中「ン」置換)。「ン/ホン」を含まない語には表示しない。ボタン無しの一行表示
- 期待効果: 詳細ページが「読み物」になり、シェアしたくなる一言が増える。

## Issue 59: 響きの近い語(vowel_pattern の類似度)
- 種別: feature
- 状態: 未着手
- 優先度: P2 ／ Impact: Med ／ Effort: Med
- 依存: なし
- 背景・現状: 2026-07-15 のアイデア出しより(条件付き採用)。脚韻(末尾一致)は語尾の型(〜ズ・〜賞)で同一ジャンルが並ぶだけになりやすい、というオーナー指摘を受け、既存の `Levenshtein` を `vowel_pattern` 全体に適用して「口の動き全体が似ている語」を出す方式にする。
- 内容:
  - [ ] 詳細ページに「響きの近い語」区画(ジャンルを墨枠チップで添え、偶然のジャンル一致も見どころにする)
  - [ ] 現状規模は全件総当たり+キャッシュで実装(Issue 52 と同種の負荷特性に留意)
  - [ ] 1万語規模で重くなったら近傍を中間テーブルへ事前計算(効率化のための後付けテーブルは方針の例外規定どおり)
  - [ ] Issue 57 の散歩軸(「響きが近い語へ」)としても共用
- 期待効果: `vowel_pattern` を使った独自の回遊導線。類似サイトに無い差別化要素。

## Issue 60: 母音子音パターン図鑑
- 種別: feature
- 状態: 未着手(着手時に窓幅 k の段階と符号ルールを最終確定)
- 優先度: P2 ／ Impact: Med〜High ／ Effort: Med
- 依存: なし
- 背景・現状: 2026-07-15 のアイデア出しより(採用。オーナー発案)。読みの各拍を v(母音拍)/c(子音拍)に符号化し(例: ありがとう=vcccv)、パターンの網羅状況を図鑑として見せる。全長パターンは 2^n で爆発しほぼ全語が固有パターンになる(埋まらない図鑑になる)ため、二層構造にする。
- 内容:
  - [ ] v/c 符号化の値オブジェクト(ん・っ=c、長音ー=v、拗音は直前に併合。`MoraCount`/`RhythmPattern` と拍分割の規則を揃える)
  - [ ] 第1層「k 拍の律動図鑑」: 語中に現れる k 拍の窓をすべて発見扱いにするグリッド(k=4〜7 を難易度別ページに。1語が多数の枠に寄与するため序盤から埋まる)。発見済みマスから該当語一覧へ(検索導線化)
  - [ ] 第2層「全長パターン」: 拍数ごとの発見カウンタ+未発見パターンの指名手配(募集)表示。鑑定書(Issue 58)に「このパターンは本語のみ」を連携
  - [ ] 集計はメモリで開始し、逆引きが重くなったら Ruby 生成カラム+インデックスへ昇格(`char_type_pattern` と同作法。例外規定どおり)
- 期待効果: 収集の快感による再訪動機。未発見枠が将来のリクエスト機能の受け皿・動機になる(それまでは連絡先メールへの導線で代替)。

## Issue 61: しりとり道場(DB と対戦するしりとり)
- 種別: feature
- 状態: 未着手(**着手前に相談**。ルール詳細・置き場所が未確定)
- 優先度: P2 ／ Impact: Med ／ Effort: Med
- 依存: Issue 57(しりとり遷移のクエリが土台)
- 背景・現状: 2026-07-15 のアイデア出しより(候補)。全収録語が読み10文字以上のため、DB が「一方的に長い語で殴り返してくる理不尽なしりとり相手」になる非対称性自体が笑いどころ。
- 内容:
  - [ ] ユーザーはかなで入力(辞書判定はしない。自己申告制と明記)。DB 応答は `first_char` の1クエリ
  - [ ] 使用済み語は Stimulus でクライアント保持(DB 書き込みゼロ・セッション不要)
  - [ ] DB が「ん」終わりの語しか返せなくなったら「参りました」画面+X 共有(共有導線は実装済み)
  - [ ] 応答語はすべて詳細ページへのリンクにして回遊導線化
- 期待効果: 遊べる看板機能。SNS で共有されやすい。
- 補足: 頭文字の在庫が薄い文字があると即詰みするため、収録数が増えてからの公開が安全。

## Issue 62: 五十音円環(頭文字→末尾文字の遷移ビジュアル)
- 種別: feature
- 状態: 未着手
- 優先度: P2 ／ Impact: Med ／ Effort: Med〜High
- 依存: Issue 34(統計ページ。その看板ビジュアルとして実装)
- 背景・現状: 2026-07-15 のアイデア出しより(採用。ただし「統計データっぽい」というオーナー評のため単独ページにせず統計ページの看板に位置づける)。五十音を円環に並べ、頭文字→末尾文字の遷移を弦で結ぶコード図。データは `GROUP BY first_char, last_char` の1クエリで取れる。
- 内容:
  - [ ] インライン SVG で描画(墨線、通過量の多い弦のみ朱。チャートライブラリ不使用、design.md 準拠)
  - [ ] 弦タップでその遷移(頭文字◯→末尾△)の語一覧へ(検索導線化。design.md §5.5)
  - [ ] 「る」への集中・「ん」の行き止まりなどをキャプションで読み物化
- 期待効果: 統計ページの看板。スクリーンショット共有・被リンクの獲得。

## Issue 71: 正規表現ビルダー(/search/regexp)
- 種別: feature
- 状態: 未着手
- 優先度: P2 ／ Impact: Low〜Med ／ Effort: Low〜Med
- 依存: なし(前提の正規表現検索は Issue 9 の一部として実装済み。`SearchRegexp` / `WordSenseSearch#regexp`)
- 背景・現状: 2026-07-16 のオーナー提案より(採用)。詳細検索に正規表現条件を入れたが、書ける人しか使えない。「〇で始まる」「△をn回繰り返す」のような操作を選ぶとパターン文字列を組み立てるページを、フロント(Stimulus)のみで用意する。検索フォームには畳んだ早見表(`searches.regexp_help`)があり、その一段上の学習導線という位置づけ。
- 内容:
  - [ ] ルーティングは `get "search/regexp"`(検索の道具なので検索の下。`/help/*` の階層は作らない = ヘルプ体系は存在せず、1ページのために枠を名乗らない)
  - [ ] 操作は**既存フィルタで表現できないもの**に絞る: 繰り返し(`ア{3}`)/選択(`(キョウ|トウ)`)/位置関係(`カ.*ン`)/文字クラス・否定(`[^アイウエオ]`)。
        「〇で始まる」「×で終わる」は先頭文字・末尾文字の50音表、文字種は char-type コンソールが既にあり、そのまま並べると入口が二重になり劣化版になる。入れるなら既存 UI への誘導を添える
  - [ ] 組み立てた式は「この式で検索」で `/search?regexp=...` に渡すだけにする
  - [ ] **その場のプレビュー(JS の RegExp で試し打ち)は作らない**: 実際の判定は MySQL の ICU で方言が違い、かつ読みはカタカナへ畳んでから当てるため、プレビューは当たったのに検索は0件という食い違いが起きる。判定は MySQL 一箇所に保つ
  - [ ] design.md 準拠(墨1px枠のパネルで操作行を積む。角丸・影なし、チャート/外部ライブラリ不使用)
- 期待効果: 正規表現を書けない層にも独自の検索軸を開く。「項目の多さが見どころ」の路線に沿った見せ場。
- 補足: 使う人が限られる懸念がある(書ける人は直接書く)。反応が読めないうちは、早見表の記法を動く検索リンクにするだけの安価な代替でも学習効果は近い。

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

## グロース戦略対応(Issue 42〜48、2026-07-12 の [`growth-strategy.md`](growth-strategy.md) より)

- **Issue 42: プライバシーポリシー /privacy** [feature] — 完了(PR #82)。外部送信規律の公表事項(GA4 の送信先・送信される情報・利用目的)・Cookie・アクセスログ・連絡先。フッター・About・llms.txt・sitemap から参照。
- **Issue 43: インデックス解禁スイッチ** [improvement] — 完了(PR #82)。`INDEXING_ENABLED` 未設定 = 全ページ noindex(ページ個別指定より優先)。解禁手順は [`launch-checklist.md`](launch-checklist.md)。テスト環境の既定は「解禁後」(test.rb)。

(Issue 44〜48 は未完了節を参照)

## 技術監査対応(Issue 49〜56、2026-07-12 の監査より)

- **Issue 49: deploy:seed × マスタリネームの重複再発防止** [bug] — 完了(PR #73)。対策方式は「案a+b(リネーム追従マップ + UI警告)」をオーナー決定。マスタの名前リストを `app/models/seed_catalog.rb`(単一の正)に集約し、seed 実行時に RENAMES(旧名→新名)で全環境が改名に追従。移行先が既存の場合は改名せず警告(統合は /admin/tags に委ねる)。タグ統括管理には seed 収載タグの「seed」印(一覧)と更新手順の警告(編集画面)を表示。旧 `db/seeds/*.rb` 4本は削除。
- **Issue 50: 管理者セッションの有効期限** [improvement] — 完了(PR #71)。永続 Cookie(約20年)を2週間の `expires` に変更。サーバ側も `updated_at` ベースのスライディング失効(`Session::LIFETIME`)を導入し、期限切れはアクセス時に破棄・ログイン時に掃除。DB 書き込みと Set-Cookie は1時間間隔に間引き。
- **Issue 51: backfill タスクの last_char 再計算漏れ** [bug] — 完了(PR #72)。`backfill:reading_metrics` に `last_char` の再計算を追加。全派生カラム(words.char_type_pattern 含む)の現在値と再計算値の差分を報告する読み取り専用タスク `backfill:verify` を新設。verify がフィクスチャの実バグ(涼宮ハルヒの憂鬱の char_type_pattern で「の」が文字クラス化されていない)を検出したため同時修正。

## アノテーション高速化(Issue 63〜70、2026-07-16 の UX 調査より)

未注釈約6,000語を「質と量を同時に」捌くため、提案キューの操作を減らす改善群。管理者ロールプレイでコンソールを調査し Issue 63〜70 を起票。3軸(スキルで情報取得 / テキスト入力を極力させず自動 fill / ボタン操作でタブレット可)を強化する。

- **Issue 63: 提案の言語的特徴を表示・反映** [bug/improvement] — 完了(PR #88)。payload に眠っていた特徴(`senses[].linguistic_features`)を提案パネルに表示し、反映時に `word_sense_features` を build(未知名は新設候補・`target_start` はモデルが補完)。
- **Issue 64: 提案あり語のロード時自動反映** [improvement] — 完了(PR #88)。`?proposed=1` で pending 提案を開いた時点で自動反映(`apply_proposal?`。提案 > スティッキー)。毎語の「提案を反映」1クリック+GET 往復を廃止。
- **Issue 65: 提案の一括承認** [feature] — 完了(PR #88)。`BulkProposalApproval`(厳格ゲート=high/立項≥4/単一語義/全マスタ解決/新設0)でプレビュー→一括承認・公開。反映は `ProposalApplication` に共通化(語種 join は GET=target 差替 / 保存=setter)。
- **Issue 66: 新設マスタのワンタップ作成** [improvement] — 完了(PR #89)。提案パネルの「新設候補」を作成ボタン化(`ProposedMasterCreation`。`POST create_master` → 作成して `apply_proposal=1` で再反映)。エンティティ/品詞/語種/ジャンル小分類に対応(特徴は create 口が無く対象外)。
- **Issue 67: キューの並べ替え/フィルタ** [improvement] — 完了(PR #90)。`?proposed=1` に `review`(要判断=立項≤3 or 確信 low の `needs_review` scope)と `sort`(easy=確実な順 / review=要判断を先に。payload JSON を SQL で並べ替え)を追加。ナビゲーション(index/skip/戻る/保存後移動)を並び順追従に。`nav_params` でリンク・フォームに持ち回る。
- **Issue 68: 公開事故ガード** [improvement] — 完了(PR #91)。方式は「保存時 confirm」(オーナー選択)。`publish-guard`(Stimulus)が「保存して次へ」で全語義が最低限(is-complete)未達なら確認を挟む。完了済み・保留は無確認。状態モデルは変えない軽量案。

(Issue 69〜70 は未完了節を参照)

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

## 2026-07-15(公開側エンタメ機能のアイデア出し)

10. **採用**: ことばの散歩(Issue 57)・鑑定書+ンホホ変換一行(Issue 58)・響きの近い語(Issue 59)・母音子音パターン図鑑(Issue 60)・しりとり道場(Issue 61、着手前に相談)・五十音円環(Issue 62、統計ページの看板として)。いずれもテーブル・カラム追加なしで開始し、規模拡大時のみ効率化目的の後付け(生成カラム・事前計算テーブル)を許容する。
11. **不採用**: 最長語番付(一覧のソートで足りる)・逆さ読み/回文・隠れ単語(読み10文字以上の収録語では偶然の一致がほぼ起きない)・長音無限化(メモ帳で再現できる)。汎用「ことばの遊具」変換ページも作らない(ンホホ変換のみ詳細ページの一行に)。
12. **保留**: 読み切りメーター(拍を一定テンポで点灯させ長さを時間で体感させる案。趣旨が伝わる形で要再提案)・リクエスト機能(要件を詰めてから。図鑑の「未発見募集」が将来の受け皿)。
13. **ガチャ的な演出はしない**。希少性の表現は標本ラベル風の文言と朱の一文字印程度に抑える(活字見本帖の雰囲気を優先)。「今日の一語」は実装済みのため対象外。

## 2026-07-16(アノテーション高速化の UX 調査)

14. **アノテーション高速化の思想**: (a) Claude Code スキルで情報取得、(b) テキスト入力を極力させず自動 fill、(c) ボタン操作でタブレット/スマホでも捌ける、の3軸を維持・強化する。この観点でコンソールを調査し **Issue 63〜70** を起票。優先度の高い順(P1: 63→64→65)に着手する。
15. **旗艦 = Issue 63**(提案の言語的特徴が表示も反映もされず捨てられている問題)から実装に入る。投資対効果が最も高い(手作業で最も重い範囲タップの自動化)ため。
