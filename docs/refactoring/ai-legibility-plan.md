# AI 向け可読性改修の計画書

> **状態: 承認待ち（台帳の段階 3）**。承認されるまでコードは変更しない。
> これは改修の作業計画であり、現行仕様の正ではない（正は `CLAUDE.md`・`docs/` の各文書・コード）。
> - 進め方の決まりは [`STRATEGY.md`](STRATEGY.md)、**どの項目が済んだかは [`LEDGER.md`](LEDGER.md) だけが持つ**。
>   この文書は項目の中身（何をなぜ直すか）だけを書き、状態は書かない。
> - 2026-09-30 の初版を、2026-10-03 に台帳の段階 2（棚卸しと補完監査）の結果で改訂した（P-01）。
> - **用語**: この文書の「区分 T0〜G4」は改修項目の種類（特性テスト・文書・残骸・集約・案内）を指す。
>   台帳と STRATEGY の「段階 0〜5」は進め方の段取り（目的の確定・監査・計画・実行・片付け）を指す。初版では両方を「段階」と呼んでいた。
> - 改修が終わったら、この文書と監査記録（[`audits/`](audits/)）は `docs/history/` へ移す（G4-05）。

## 0. 前提

### 0.1 目的

人間はコードを書かず、将来の AI エージェントが保守する。**将来のエージェントがコードを誤解せず、
最小の探索で正しい変更ができる状態**にする。評価基準は次の4つ。

1. コード・コメント・docs・命名が互いに矛盾していない（嘘の情報がない）
2. 同じ種類の処理は1つの正典パターンで書かれており、手本が一意に決まる
3. 派生値・副作用・データの出どころが、該当箇所から辿れる
4. 「どこに何があるか」を探す手数が少ない

### 0.2 この改修の制約

- 作業はブランチ `feature/refactoring` の 1 本だけで行う（STRATEGY §5）。
  **main への push・merge は、そのまま本番デプロイになる**。`.github/workflows/deploy.yml` は main への push で動き、CI の完了を待たない。
  main にはブランチ保護も無い（2026-10-02 に `gh api` で確認）。push・PR・merge は、オーナーの指示があるときだけ行う。
- 外部から見える振る舞いを変えない: 公開ページの URL と HTML の意味構造、JSON API のレスポンス形式、
  og:image、収録リクエストフォーム、管理者認証、テキストの公開出力（robots.txt・llms.txt・llms-full.txt・sitemap・Atom）、
  HTTP の鮮度判定（ETag・Cache-Control）。
  - 例外: 運用タスク（`backfill:*`）の欠陥の修正は、公開の表示を変えない範囲で行う。rake が書く値と出力は変わる（C3-12。P-02 の PR-10）。
  - 管理画面も、操作の結果（保存される値・絞り込み・表示される値の書式）は変えない。変えるものは §7.1 に回す。
  - ただし、管理画面の**説明文・プレースホルダ・案内の文言を事実に合わせる**ことは、区分 D1 に含める（D1-06・D1-14・D1-20）。
    管理画面は作業するオーナー 1 人だけが見る画面で、事実と違う案内は嘘の一種なので。公開側の文言を変えるのは §7.1。
- 適用済みの `db/migrate` は書き換えない。スキーマは変更しない（必要なものは §7 に提案として書くだけ）。
- 照合順序の規約（全体 `utf8mb4_0900_ai_ci`、読み・表層形のカラムだけ `utf8mb4_0900_as_ci`）を維持する。
- 「しずか」の方針を維持する（web フォント無し・JS 最小限・CSS フレームワーク無し・importmap のまま・ビルドツールを入れない）。
- MeCab / rsvg-convert が無い環境でも機能が止まらないフォールバックを維持する。
- gem・JS ライブラリを追加・削除しない。
- 既存テストの期待値を変えない。変える必要がある項目は実施せず、§7.3 に理由を書く。
- コミットには `git add <パス>` で明示したファイルだけを含める。
  初版の時点で所有者の作業中だった `README.md`・`.claude/commands/expand.md`・`.claude/skills/word-expansion-research/` は、
  その後コミットされた（83e36d2・f7b88da）。そのため改修の対象に戻した（初版の §7.6 は廃止）。

### 0.3 合格判定（各コミットで全て満たす）

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit check --update
bin/importmap audit
bin/rails test
CHROME_BIN=<Selenium Manager が選ぶ chromedriver と同じメジャーの Chrome> bin/rails test:system
```

- 連結形の `bin/rails test test:system` はローカルでは `LoadError` になる（§1）。2本に分けて実行する。
- 失敗したら直すか、そのコミットを取り消す。満たさないまま次の項目へ進まない。
- `docs/refactoring/` だけを変えるコミット（台帳・計画書・監査記録）は、合格判定を省いてよい（STRATEGY §2.3）。
- 既知の不安定なテストが1本ある: `test/system/admin_annotation_deck_test.rb` の「提案の新設候補をその場で作ると…」は、
  変更と関係なく落ちることがある（CI では通っている）。これだけが落ちたら、再実行して再現するかを確かめる。

## 1. ベースライン（2026-09-27 計測。main = `a04f375`）

| チェック | 結果 |
|---|---|
| `bundle exec rubocop` | 310 files inspected, no offenses |
| `bundle exec brakeman --no-pager` | No warnings found |
| `bundle exec bundler-audit check --update` | No vulnerabilities found |
| `bin/importmap audit` | No vulnerable packages found |
| `bin/rails test` | 785 runs, 15300 assertions, 0 failures, 0 errors, 1 skip（rsvg-convert が無いため共有カードの描画テストが skip） |
| `bin/rails test:system`（Chrome 154） | 26 runs, 220 assertions, 0 failures, 0 errors |

アサーションの数は、同じコードでも実行のたびに数件ずれる（条件によって assert する経路があるため）。
2026-09-30 にこの計画書を足して再実行したときは 15301 件 / 218 件で、失敗は 0 だった。

**a04f375 以降、`app`・`config`・`lib`・`db`・`test`・`vendor`・`script`・`tools` に差分は無い**（2026-10-03、HEAD = `1110261` で確認）。
そのため、このベースラインと監査記録の行番号は、そのまま使える。
ただし Chrome の版などの環境は動くので、**台帳の段階 4（実行）の最初に合格判定を一度通して、ベースラインを取り直す**（§6）。

計画の前提として、統合担当が実行して確かめた事実は次の2つ。

- **`bin/rails test test:system` はローカルでは `LoadError` になる**。`test:system` をファイルパスとして読むため。
  CI は `bin/rails db:test:prepare test test:system` で通っている（先頭が rake タスクなので、全体が rake タスクとして解釈される）。
- **照合順序の実測**（docker の開発用 DB で、文字列リテラルどうしを比較した。データには触れていない）。
  2026-09-27 に as_ci の列を、2026-10-02 に ai_ci の列・全角英字・末尾の空白を測った（MySQL 8.4.10。補完監査 A-06 のリーダーの裏取り）。

  | 比較 | `utf8mb4_0900_as_ci` | `utf8mb4_0900_ai_ci` |
  |---|---|---|
  | ハ / バ（清濁） | 区別する | 同一視する |
  | ヤ / ャ、ツ / ッ（小書き） | **同一視する** | 同一視する（ヤ / ャ で計測） |
  | あ / ア（ひらがな・カタカナ） | 同一視する | 同一視する |
  | ア / ｱ（全角・半角のカナ） | 同一視する | 同一視する |
  | Ａ / A（全角・半角の英字） | 同一視する | 同一視する |
  | A / a（大文字・小文字） | 同一視する | （未計測） |
  | ー / -（長音符・ハイフン） | 区別する | （未計測） |
  | 「名詞␣」/「名詞」（末尾の空白） | 区別する | **区別する**（0900 系の照合順序は NO PAD） |
  | `REPLACE()` | 照合順序によらずバイナリで比較する | — |

## 2. 監査の概要

監査は 3 回に分けて行い、改訂した計画書を 1 回反証レビューした。どれも読み取りだけで、コードは変えていない。

| 回 | 時期 | 内容 | 記録 |
|---|---|---|---|
| フェーズ1 | 2026-09-27〜30 | 8 領域の監査（指摘 154 件） | [`audits/*.md`](audits/)（§2.1） |
| 棚卸し | 2026-10-02 | フェーズ1 の指摘を、いまの HEAD に照らして仕分けた（B-01〜B-08） | 各監査記録の末尾の「棚卸し」節（§2.2） |
| 補完監査 | 2026-10-02 | フェーズ1 で確かめきれなかった範囲を 10 単位で調べた（A-01〜A-11。A-03 は見送り。指摘 93 件） | [`audits/supplement/A-*.md`](audits/supplement/)（§2.3） |
| 反証レビュー | 2026-10-03 | 改訂した計画書をコードと突き合わせて、誤りを探した（P-02。指摘 16 件。PR-1〜PR-16） | [`audits/plan-review.md`](audits/plan-review.md)（§9 の PR の行） |

### 2.1 フェーズ1

8体のサブエージェントが読み取りだけで監査した。docs は分量が多いので2体に分けた。
報告の全文は [`audits/`](audits/) にある（行番号は `a04f375` 時点のもので、いまも有効。§1）。

| 領域 | ID | 件数 | 報告 |
|---|---|---:|---|
| app/models・services・jobs | M- | 21 | [audits/models.md](audits/models.md) |
| controllers・helpers・views | C- | 23 | [audits/controllers-views.md](audits/controllers-views.md) |
| app/javascript | J- | 20 | [audits/javascript.md](audits/javascript.md) |
| app/assets/stylesheets | S- | 13 | [audits/stylesheets.md](audits/stylesheets.md) |
| db・config・lib・CI | CFG- | 18 | [audits/db-config.md](audits/db-config.md) |
| test | T- | 19 | [audits/test.md](audits/test.md) |
| 案内系の文書（CLAUDE.md・overview・data-model・スキルなど） | DOC- | 16 | [audits/docs-guides.md](audits/docs-guides.md) |
| 仕様・記録系の文書と、それを参照するコメント | SPEC- | 24 | [audits/docs-specs.md](audits/docs-specs.md) |

- 監査は利用上限で2回中断し、再開したときに残りを重要な項目に絞った。確認しきれなかった範囲は、各報告の末尾の「未確認のまま残した範囲」に書かれている。
- 各指摘には確度（確認済み / 推測）が付いている。**計画に採用した推測には「要確認」と書き、実行（台帳の段階 4）で実測してから着手する。**
- 統合担当が実物で裏取りした主な指摘は次のとおり。
  - DOC-01（deploy.yml）、DOC-02（テストコマンド）、DOC-03（スキルの旧フロー）、DOC-04（as_ci の一覧）
  - M-01（backfill の欠落）、M-07（照合順序。§1 の実測で決着）、M-16（`unannotated` の説明）
  - SPEC-01、SPEC-02、SPEC-05、J-01、C-01
  - C-16・M-15・S-04・J-19・T-15 の未使用判定
  - §5 の集約が成り立つ前提（`WordSort` の新着順が既存の並びと同じこと、stimulus-loading が `_controller` で終わるファイルしか登録しないこと、TTL の値が一致すること）
- 不採用にした指摘は2つ。
  - M-13 のうち `WordCandidateIntake` のコメント。「1行の失敗で他の行を巻き戻さない」は実装と合っている。
  - `WordSort::RANKING_KEYS` の削除。テストが参照している。

### 2.2 棚卸し（B-01〜B-08）

- **陳腐化した指摘は 0 件**。a04f375 以降、コードが 1 行も変わっていないため（§1）。
- 監査どうしで同じ事実を指している指摘は、§9 の対応表で同じ改修項目に束ねてある。二重には数えない。
- 監査の後にコミットされた README・/expand のスキルを照合して、**新しい指摘を 5 件**足した。
  - T-20: system テストが、もう読んでいない Google Fonts を遮断している（[audits/test.md](audits/test.md) の棚卸し節）。
  - DOC-17: README のジョブの行が、ジョブの実在を示唆する。
  - DOC-18: README の「コードベースの規模」は、放っておけば古くなる数値。
  - **DOC-19: /expand のスキル（`reading_length.rb`）が、`ReadingExtractor` の private メソッド `normalize` を `send` で呼んでいる**。
    `.claude/` は RuboCop の対象外で、テストも無い。C3-04・C3-15 で ReadingExtractor を変えると、/expand が黙って壊れる。
  - DOC-20: /expand のスキルにも、DOC-03 と同じ旧フローの記述が残っている。
  - DOC-17〜20 の詳細は [audits/docs-guides.md](audits/docs-guides.md) の棚卸し節にある。
- 確度を**推測から確認済みに上げた**もの。
  - J-20: Plotly が importmap にピンされていない（`config/importmap.rb` に pin が無い）。
  - C-20: マスタを新設する経路が揃っていない（補完監査 A-06 で裏取り。本番の経路は seed を入れて 4 系統）。
  - SPEC-13: コンソールで読み 10 字未満の語義を保存できる（`WordSense` の検証は presence だけ。コードで確認。実行はしていない）。
  - S-09 の前提: /admin 配下のコントローラは 19 本すべて `Admin::BaseController` 系（`bin/rails routes` で確認）。
- 棚卸しで決着した確認事項（主なもの）。
  - transactional test の中で after_commit は動いている（`word_sense_metrics_test.rb:41` が通っている）。
  - test/integration・test/helpers は data 属性を固定していない。
  - 読みの更新で `reading_density` が追従することのテストは無い（作成時と表層形の更新時はある）。→ T0-13
  - `tools/claude-ai-skill/build.sh` の description が SKILL.md と違うのは意図的（バンドル版は一括の調査も受ける）。指摘にしない。
  - reading_length.rb は RuboCop の対象外。
- 見送ったもの。
  - A-03（seed まわりの精読）。CFG-05〜CFG-07 で覆われていた。
  - 記録の文書（issues.md・changelog.md・performance-report.md）を 1 行ずつ照合すること。記録であって現行の仕様ではないので、照合する代わりに G4-02 で隔離する。
  - Issue を参照する約 274 行のコードコメントの事前照合。§4.7 のコメントの扱いに従って、G4-04 で書き換える。

### 2.3 補完監査（A-01〜A-11）

| 単位 | 対象 | 件数 | 報告 |
|---|---|---:|---|
| A-01 | 派生値の再計算（`stats_helper.rb`・`feature_range_controller.js`） | 7 | [A-01](audits/supplement/A-01.md) |
| A-02 | `MorphemeCloud`・`ShareCardTypesetter` の内部コメント | 10 | [A-02](audits/supplement/A-02.md) |
| A-04 | 管理ビューの精読（35 ファイル） | 15 | [A-04](audits/supplement/A-04.md) |
| A-05 | 統計・共有パーシャルと stats.md §4〜§8 | 12 | [A-05](audits/supplement/A-05.md) |
| A-06 | マスタを新設する経路の正規化と検証（C-20 の裏取り） | 7 | [A-06](audits/supplement/A-06.md) |
| A-07 | CSS に定義の無いクラス名（逆方向の照合） | 5 | [A-07](audits/supplement/A-07.md) |
| A-08 | 提案 JSON の形式（スキル ⇔ 取り込み ⇔ 反映） | 10 | [A-08](audits/supplement/A-08.md) |
| A-09 | 公開スコープの全経路（未公開語の漏れ） | 3 | [A-09](audits/supplement/A-09.md) |
| A-10 | design.md の未照合の節 | 11 | [A-10](audits/supplement/A-10.md) |
| A-11 | 収録基準ガイドラインと各スキル・マスタ | 13 | [A-11](audits/supplement/A-11.md) |

- 指摘の ID は単位ごとに `A01-1` の形で振った。各報告の末尾に「リーダーの裏取り」節があり、リーダーが実物で確かめた事実を書いてある。
- **未公開の語が公開面に出る経路は無かった**（A-09）。ただし、公開を取り消した語がキャッシュに最大 1 日残る（A09-1。§7.5）。
- リーダーが実物で確かめた主な事実。
  - A04-1: 特徴の再調査の書き出しで、「日本語のみ」のチェックを外しても絞り込みが外れない（管理画面の不具合）。
  - A09-1: sitemap・llms-full の版（`PublishedWordsDigest`）は、公開語が減っても変わらない。これは性能のための意図的な割り切りとして、`published_words_digest.rb` のコメントに書かれている。
  - A06-1: マスタ名の前後の空白を落とすのは、その場追加（`InlineMasterCreatable#inline_master_name`）だけ。照合順序は末尾の空白を区別する（§1 の表）。
  - A10-1: ΔRGB を、テストは各チャンネルの差の合計、`layout.css` のコメントと design.md は最大差で測っている。
  - A05-4: 母音遷移の上限 15 が、`SiteStatistics::TRANSITION_MAX_POSITIONS` と `WordSenseSearch::VOWEL_TRANSITION_FORMAT` に別々に書かれている。
  - A08-2: `genre_new` を読む箇所は無い（キーの一覧に現れるだけ）。
  - A02-5: `.word-cloud__text` の `paint-order: stroke` は、stroke がどこにも無いので効いていない。
  - A07-1: `sense-attrs__item--wide` は、CSS が 1f51389 で消えた後もビュー 3 か所に残っている。
  - A11-3・A11-11: /harvest の例「メイショウタバル」は 8 文字。注釈スキルが「マスタに無い言語」の例にした「ギリシャ語」は、SeedCatalog に実在する。
  - A01-5: `stats_helper.rb` の「15 層で 818px」は、実装の式では 1,148px。
- 反証レビュー（P-02）で、A05-9 の「テストが参照していない」は、2 つの `total` については誤りと分かった（PR-3。R2-01 から外した）。
- A11-2 の判断材料として、開発用 DB のデータを数えた（2026-10-03。読み取りのみ）。ひらがなを含む `word_senses.reading` は 1,631 件中 0 件、ひらがなを含む `word_sense_features.target_reading` は 262 件中 0 件だった。

## 3. 横断的な発見

1. **AI が最初に読む案内文書に、操作を誤らせる嘘がある**。
   - main への merge がそのまま本番デプロイになり、CI の完了を待たないことが、どこにも書かれていない。
   - 合格判定コマンドが4か所で、動かない形のまま書かれている。
   - as_ci の一覧から word_candidates が抜けている。
   - 「backfill を流せば派生値が直る」と書いてあるが、直らない列がある。
2. **派生値の組み立てが3か所に複製され、すでに1回ずれている**。
   - `ring_crossing_count` はモデルが算出するが、`backfill:reading_metrics` も `backfill:verify` も扱っていない。
   - STORED の `words.reading_density` が、after_commit で作る `max_reading_length` に依存していることも書かれていない。
3. **同じ規則の実装が複数ある**。かなの畳み込み8通り、調査 JSON の読み取り3通り、絶対 URL の組み立て10か所以上、
   代表語義の選び方2通り、管理画面の判定2通り、キャッシュの書き方3系統、しきい値の別名定数と直書き。
4. **嘘の最大の供給源は、経緯を書いたコメントが古くなったもの**。「アクセント」「朱」「太字」「印章」「検索パネル」など、
   撤去済みの設計の語彙が残っている。コメントに日付・Issue 番号・計測値を積むほど古くなる。
5. **範囲外の不具合も見つかった**（§7.1）。直すと振る舞いが変わるので、この改修では直さずに記録する。
   補完監査で増えた主なものは次のとおり。
   - 管理画面の「日本語のみ」の絞り込みが外れない（A04-1。確認済み）。
   - 公開を取り消した語が、キャッシュに最大 1 日残る（A09-1。意図的な割り切りかどうかをオーナーに確認する）。
   - 特徴の位置 `target_start` を誰も検証していない（A01-1）。
   - 不完全な特徴が黙って落ちたまま公開される（A08-6）。
   - 一括承認が 1 件の不備で全件を巻き戻す（A08-7）。
   - 閉じたドロワーがキーボードのフォーカス順に残る（A10-4）。
6. **調査パイプライン（スキル → 提案 JSON → 取り込み → 反映）の約束が、文書の側にしか書かれていない**。
   - 提案 JSON のキーの一覧が 8 か所にある（M-05・A08-1）。
   - `genre_new`・`target_start` は、スキルが書いても黙って捨てられる（A08-2・A08-3）。
   - 必須の取り決めは SKILL.md にしか無く、schema.json と食い違う（A08-4）。
   - 注釈の規則の正がガイドラインとスキルのどちらにあるかが、文書どうしで食い違う（A11-1）。
   - スキルがアプリの private メソッドに依存している（DOC-19）。アプリ側を直すと、スキルが黙って壊れる。
7. **同じ「名前が一致するか」の判定が、DB の照合順序と Ruby の比較で混ざっている**。
   - マスタを新設する経路は 4 系統あり、名前の正規化（前後の空白の除去）は 1 系統にしか無い（C-20・A06-1）。
   - 新しく作る名前が既存の名前と衝突したときの扱いも、3 通りある（A06-2）。
   - マスタ名の一致を、SQL は ai_ci で、Ruby は完全一致で判定している箇所がある（A06-4）。
8. **1 つの規則を測る式・判定が複数ある**。
   - CLAUDE.md の「ΔRGB 19 以上」を、テストは各チャンネルの差の合計、文書とコメントは最大差で測っていて、合否が入れ替わる（A10-1）。
   - 分布の最頻値（A01-4）、母音遷移の上限 15（A05-4）、フレーム幅 1040px（A10-8）も、それぞれ 2〜4 か所に別々に書かれている。
9. **新しい管理画面ほど、正典が決まる前に作られている**。
   - 登録予定単語（#162〜#164）は、段の定義があちこちに散らばっている（A04-7・PR-9）。
   - 提案パネル・JSON のコピー欄・用語解説パネル・下端のバーが、画面ごとに複製されている（A04-3・A04-4・A04-9・A04-10）。
   - パーシャルのローカル変数の受け方が 3 通りある（A04-14）。
   - 正典を先に決めて手本を示すと、次に足す画面の書き方が揃う（§4）。

## 4. 領域ごとの正典パターン（定義案）

改修後の CLAUDE.md（G4-01）に載せる定義の案。「区分 C3 の後」と書いたものは、その項目が終わるまでは既存の手本を使う。

### 4.1 モデル・サービス

- **置き場所**
  - `app/models` には ActiveRecord と、それ以外の Ruby をすべて置く（値オブジェクト・クエリ／集計・書き込み処理・フォーム・調査 JSON の入出力）。
  - `app/services` には**外部プロセスを起動するラッパーだけ**を置く（手本 `share_card_renderer.rb`）。
  - `app/models/concerns` には、複数のモデルが include する振る舞いを置く。
  - サブディレクトリは作らない（定数名が変わるため）。
- **クラス冒頭の種別ラベル**は次の5語に揃える。
  - 値オブジェクト（DB に触れない）
  - クエリ・集計（読み取りとキャッシュ）
  - 書き込み処理
  - フォーム
  - 調査 JSON の入出力
- **派生値**
  - 手入力させない。次の3つのどれかで作る: SQL の STORED 生成カラム／値オブジェクト＋`before_validation`／`after_commit` で焼き直す代表値（`WordSenseMetrics`）。
  - 値オブジェクトは `self.call(input)` の純粋関数にする（手本 `last_char.rb`・`char_type_pattern.rb`）。
    変換が複数ある値オブジェクト（C3-15 の `KanaFold` など）は、`to_katakana` のような名前付きのクラスメソッドにする（P-02 の PR-16）。
  - 読み由来の値の組み立ては `WordSense.reading_derivations(reading)` の1か所だけにする（区分 C3 の後）。
  - **派生列を足したら、data-model.md §3 の表・backfill・verify を同じコミットで直す。**
- **コールバックを通らない更新**（`update_all`・`update_columns`・生 SQL）には、その場で理由をコメントし、事後の直し方（backfill）を示す。
- **集計とキャッシュ**
  - 版付きの `CACHE_KEY`・`CACHE_TTL`・`RACE_CONDITION_TTL` を持つクラスメソッドにする（手本 `site_statistics.rb`・`published_sense_counts.rb`）。
  - 無効化は TTL だけで行う（`Rails.cache.delete` は使っていない）。
  - 既知の例外（P-02 の PR-12）: `WordRanking` は race_condition_ttl を持たない（M-18。§7.1）。`WordRequestDuplicateCheck.cache_key` のキーには版が無い（§7.7）。
    そのため、公開の取り消し（保留・削除）も TTL のあいだは反映されない。これを許すかはオーナー判断（§7.5・A09-1）。
  - **図や表の「印」（最頻のビン・最多の行・各行の比率）は、集計クラスが決めて返す**。ヘルパとビューは、それを座標や class に写すだけにする（A01-4・A01-7・A05-10）。
    既存の二重計算は区分 D1 で注記する。揃えるのは、端の場合の表示が変わるので §7.1。
- **基準値・しきい値**は、その概念の持ち主に1つだけ置く。別名の定数は作らない。
  - `WordSense::MIN_READING_LENGTH`
  - `Levenshtein::SIMILARITY_THRESHOLD`
  - 立項スコアと確信度は `AnnotationProposal`（区分 C3 の後）
  - マスタ名は `SeedCatalog`
- **調査 JSON の入出力**
  - 取り込みの手本は `word_candidate_notation_import.rb`。`ResearchJson.array_at` で読む。入口は `call`。形が読めなければ nil を返す。外側のトランザクションに加えて行ごとに `requires_new` を張る。結果は `Struct(keyword_init: true)` で返す。
  - 書き出しの手本は `annotation_research_export.rb`。`as_json` / `to_json` に VERSION を付ける。
  - **提案 JSON のキーの正は `AnnotationProposal` の定数**（`SENSE_KEYS` / `META_KEYS` / `PAYLOAD_KEYS`。区分 C3 の後。C3-02）。
    取り込み・反映・再調査の書き出し・schema.json・SKILL.md は、それを参照するか写す。
    取り込みや反映で捨てるキー、保持しても読まないキーは、定数のそばに理由を書く（A08-1〜A08-3）。
- **外部コマンド**（手本 `share_card_renderer.rb`）
  - 有無の判定はクラスで1回だけ行う。
  - コマンドは配列で渡す。
  - `SystemCallError` を捕まえる。
  - タイムアウトを持つ。
  - 失敗したら nil を返し、呼び出し側が既定値へフォールバックする。
- **状態**は、間隔を空けた整数の enum で表す（手本 `word_candidate.rb`）。
- **公開条件**は、語は `Word.annotated`、語義は `WordSense.published` だけを使う。語と語義で名前が違うことを word.rb に明記する。
  - 公開側で語を読み出すクエリは、このどちらかから始めるか、これで選んだ id だけを受け取る（A-09 で全経路が守っていることを確認済み）。
  - id を預かって読み出すクラス（`WordBatch` など）は、「公開語の id だけを預かる」ことを冒頭に書く（A09-3）。
  - スコープを通らない公開出力（マスタの一覧・事前集計ファイル）と、それでも安全な理由は、data-model.md §8 の表に置く（D1-18・A09-2）。
- **かなの畳み込み**は `KanaFold`（区分 C3 の後）、**代表語義**は `Word#primary_sense`（区分 C3 の後）を使う。

### 4.2 コントローラ・ヘルパ・ビュー

- **認証**
  - `ApplicationController` が、全アクションを既定で認証必須にしている。
  - 公開側は `allow_unauthenticated_access only: %i[...]` で、開放するアクションを明示する（手本 `browse_controller.rb`）。
  - 管理側は `Admin::BaseController` を継承するだけでよい。
  - 未ログインの拒否は、`test/integration/admin_authentication_test.rb` が全ルートについて検証している。
- **Strong Parameters**
  - モデルに渡す属性は `params.require(:x).permit(...)` で受ける（手本 `word_candidates_controller.rb`）。
  - 複数の画面で共有する許可の集合は、定数1つにまとめる（手本 `Admin::AnnotationQueue::WORD_ATTRIBUTES`）。
- **並び順**は `WordSort` の定数だけを使う。新着順も `"created_desc"` を使う。
- **キャッシュ**
  - 集計値のキャッシュはモデル側に置く（4.1）。ホームと About のコントローラにある `Rails.cache` は、C3-10 でモデルへ移す（P-02 の PR-12）。
  - 全件出力の本文（sitemap・llms-full）のキャッシュは、例外としてコントローラに置く。版と TTL は `PublishedWordsDigest` のものを使う（区分 C3 の後）。
  - それ以外のコントローラには、HTTP の宣言（`expires_in` / `stale?`）だけを書く。
- **絶対 URL** は `SiteUrl` だけで作る（区分 C3 の後）。
- **ヘルパとパーシャルの使い分け**
  - 値・属性・文字列を返すならヘルパ、マークアップのまとまりならパーシャル。
  - ヘルパでは DB を引かない。引く場合はメモ化し、そのことが分かる名前にする。
  - JS に渡す値と文言は、ヘルパで data ハッシュを組んで渡す（手本 `word_requests_helper.rb` の `reading_counter_data`）。
- **i18n**
  - 表示文言は `ja.yml` に置く。
  - 新しいコードでは、キーをビューのパスに合わせる。
  - 区切り記号も i18n に置く。
- **フラッシュ**は、レイアウトの `#flash` だけに出す。
- **同じ規則を名乗る2つの画面**では、その規則を concern か定数で1か所に置く（手本 `Admin::AnnotationQueue`、`WordSense::KEYWORD_MATCH_CONDITION`）。
  - 画面の構成を決める定義（段・状態・タブ）も同じ。モデルの定数 1 つから、ヘルパ・コントローラ・書き出しが組み立てる。
    登録予定単語の段の定義は散らばっているので、C3-24 で 1 か所にまとめる（A04-7・PR-9）。
- **パーシャル**
  - 新しく作るパーシャルは、冒頭の strict locals（`<%# locals: (name:, extra_class: nil) -%>`）で受け取るものを宣言する。
  - パーシャルの中でインスタンス変数と `params` を読まない。必要な値は呼び出し側がローカルで渡す。
  - 既存のパーシャルは、区分 C3 で触るものだけ揃える。全面的な統一は §7.7（A04-14）。
- **2 画面以上で使う管理画面の部品**（提案パネルの見出しと注記、JSON のコピー欄、用語解説、選択バー）は、パーシャル 1 つにする。
  文言も i18n に 1 組だけ置く（A04-3・A04-4・A04-9・A04-10。C3-07）。
- **件数の合算や集計をビューで書かない**。コントローラか値オブジェクトが数えて渡す（A04-12・A01-7・C-17）。
- **列挙値**（確信度・状態など）は、生の値ではなく i18n のラベルで表示する（A04-8。既存の画面を直すのは §7.1）。

### 4.3 JavaScript

- **冒頭コメント**には、目的・使う画面・JS が無いとどうなるか・連携するイベントを書く（手本 `decision_list_controller.js`・`row_select_controller.js`・`panel_switch_controller.js`）。
- **Ruby の値と文言**
  - ヘルパから data 属性で渡す。JS に日本語や基準値を直書きしない。
  - 文言のプレースホルダは `%{name}` にする。
- **ページ全体に掛かるイベント**は、data-action の `@window` / `@document` で受ける（手本 `shared/_header.html.erb` の nav-menu）。
  - `addEventListener` を使うのは matchMedia などに限り、disconnect で必ず外す（手本 `theme_controller.js`）。
- **開閉状態を持つ部品**は、Turbo がキャッシュする前に閉じる（手本 `nav_menu_controller.js`）。タイマーは disconnect で clear する。
- **コントローラ同士の連携**は、`this.dispatch()` と受け手の data-action で結ぶ（手本 `sense_completeness` と `_sense_fields.html.erb`）。
  - document 全体に流すイベントは `theme:change` だけにする。
- **DOM の生成**は、サーバ側のマークアップを `<template>` target に置いて複製する（手本 `nested_form_controller.js`）。
  - createElement を使うのは、クライアントだけで描く図に限る。
- **fetch** は `inline_add_controller.js` の `post()` の形にする（CSRF・セッション切れ・JSON 以外の応答を扱う）。失敗したら必ず画面に出す。
- **共有する関数**は `app/javascript/controllers/support/` に置く。stimulus-loading は `_controller` で終わるファイルしか登録しないことを確認済み。
- **JS から要素を探す手がかり**
  - 新しく足すときは、Stimulus の target か data 属性を使う。
  - `js-` 接頭辞のクラスは既存の注釈コンソールだけに残し、増やさない。`js-` が付いていても、JS が使うとは限らない（A07-5）。
  - 見た目用のクラスを JS・テストも参照している箇所は、CSS 側に「JS（〜_controller.js）・テストも参照」と注記する。
- **操作規則を文書（stats.md など）に書いた JS** は、冒頭コメントで文書の節を参照し、規則そのものを写さない（A05-7）。
- **localStorage** の読み書きは try/catch で包む（手本 `theme_controller.js`）。
- **段階的な強化**は、サーバが全部を描き、JS が畳む（または表示する）形にする（手本 `rankings/index.html.erb` の hideOnConnect、`candidates.css` の `data-js-only`）。
- **Plotly** は、意図して importmap にピンしない。Sprockets で配信し、UMD のグローバルとして使う。そのため `bin/importmap audit` の対象外になる。

### 4.4 CSS

- **色**は `var(--token)` だけを使う。
  - 色を足すときは、tokens.css に「ライトの値＋`--dark-*`＋2つの適用ブロック」を書く（手本 tokens.css）。
  - 管理画面の色は、admin.css の `.is-admin` の1ブロックに置く。
- **並んだ要素の間の罫**は、親を `display:grid; gap:1px; background:var(--border)` にし、子を面の色で塗って作る（手本 `.entry-list` / `.entry-row`、`.rank-list`）。
- **部品の手本**
  - 丸タグ `.tag`
  - ボタン `.btn` 系
  - エラーの枠 `.form-alert`
  - 視覚的に隠す `.visually-hidden`
  - 選択状態 `.check-chip`
  - フォーカス: base.css の `:focus-visible`
  - transition: `var(--transition)`
- **置き場所の実態**（改修ではファイルを移さず、文書に書く）
  - tokens → base → layout → components の後に、annotate・candidates・admin を読む。**管理用の CSS も全ページで読まれる**。
  - layout.css にも一部の部品（nav-menu・theme-toggle・flash・admin-nav）があり、components.css にも管理画面の部品がある。
  - 読み込み順に依存する規則には、両側に注記する。
- **直書きしてよい範囲**（tokens.css の冒頭に書く）
  - 色は必ずトークンを使う。
  - 余白は、区画のリズムにはトークンを使い、部品の中の微調整の px は直書きしてよい。
  - 級数・行間は直書きしてよい（級数の正は design.md §2）。
  - ただし、**複数の部品が揃えて持つ値はトークンにする**。ヘッダー・フッター・管理ナビのフレーム幅 1040px は、4 か所に直書きされている。
    これを `--frame-width` にする（C3-21。A10-8）。
  - CSS と Ruby（ヘルパの定数）が同じ値を持つときは、ビューから CSS 変数で渡すか、両側に相手の名前を注記する（A05-4 の線の最大幅 3.2）。
    手本は、円環のアニメーションの `KanaRing.stroke_length` を CSS 変数で渡している形。
- **クラス名の付け方**（A07-3・A07-4）
  - ブロックの根は、CSS が無くても DOM の目印として付けてよい。
  - 要素・修飾子は、CSS かフック（JS・テスト）の用途があるときだけ付ける。
  - 補間で組み立てる修飾子のうち、既定の見た目に任せる値（CSS を持たない値。`--keep` など）は、そのブロックの CSS に一行で列挙する。
- **幅の切り替え**は、広い幅を基底にして、狭い幅を `max-width` で上書きする（実装の実態。`min-width` は使っていない）。
  使っているブレークポイントの一覧は design.md §7 に置く（A10-5・A10-6）。
- **淡さの下限（ΔRGB）の式**は design.md §1 で 1 つに定義する。テスト（`design_tokens_test.rb` の `delta_rgb`）とコメントは、その定義を参照する。
  - いまは、テストが各チャンネルの差の合計、文書とコメントが最大差で測っていて、合否が入れ替わる（A10-1）。
  - どちらを正にするかはオーナー判断（§7.5）。

### 4.5 DB・設定・タスク

- **読み・表層形のカラム**には `collation: "utf8mb4_0900_as_ci"` を明示し、理由を一言コメントする（手本 `db/migrate/20260924100000_create_word_candidates.rb`）。
  as_ci が何を同一視するかは data-model.md §6 に書く（§1 の実測）。
- **マスタ名**は `SeedCatalog` を唯一の正とする。コードで名前を使うときはカタログの定数を参照し、テストで固定する（手本 `test/models/linguistic_feature_glossary_test.rb`）。
  - SeedCatalog が持つのは大分類・中分類・品詞・語種・言語学的特徴の名前。小分類とエンティティ種別は DB にしか無い（調査用の書き出しの `masters` が現況を表す）（A11-11）。
  - **名前の正規化（前後の空白の除去）と、既存の名前と衝突したときの扱いは、モデルに 1 か所だけ置く**（`normalizes :name` と、`TagMaster` / `Genre` の共通メソッド）。
    新設の経路（その場追加・タグ統括管理・提案の新設候補・seed）ごとに書かない。
    いまは 4 系統でばらばらで、揃えると管理画面の振る舞いが変わるので、揃えるのは §7.1（C-20・A06-1・A06-2）。
  - 名前が一致するかは、DB の照合順序（ai_ci。§1 の表）に任せる。Ruby で比べるときは、完全一致であることと、その理由をコメントに書く（A06-4）。
  - 用語は、画面とカタログに合わせて「**言語学的特徴**」に揃える。文書とスキルに残る「言語的特徴」を直す（A11-12。画面の 3 か所を直すのは §7.1）。
- **アプリのスイッチ（環境変数）**は `config/application.rb` で1回だけ読み、`config.x` に置く（手本は同ファイルの REQUESTS_ENABLED）。
- **rake タスク**
  - 規則はモデルに任せる。
  - desc に、触る列をすべて書く。
  - 冪等にする。
  - トップレベルで `def` しない。
- **デプロイ**
  - main への push で deploy.yml が `cap production deploy` を実行する。CI の完了は待たない。
  - seed は `deploy:migrate` の直後に毎回走る。

### 4.6 テスト

- **どの層で書くか**
  - 変換・判定の規則は、値オブジェクトとモデルのテストで書く。
  - 画面の出し分け・リンク・フォームの項目名は、結合テスト（assert_select）で書く。
  - system テストは、実ブラウザ（JS の実行・レイアウトの計算）が要る挙動だけに書く。
- **管理画面のテスト**は `setup { sign_in_as(admins(:one)) }` でログインする（手本 `test/controllers/admin/candidates/lists_controller_test.rb`）。未ログインの検証は各テストに書かない。
- **テストデータ**
  - 基本はフィクスチャを使う。
  - 場面ごとに要る公開語は `create_published_word` で作る（`mark_annotated` を使う。区分 C3 の後。今の手本は `test/integration/words_feed_test.rb`）。
  - `create!` に派生値を渡さない（保存時に上書きされる）。
- **外部に出る形式**は、キーの集合ごと固定する（区分 T0 の後の `words_api_test.rb`）。
- **時刻**は `travel_to` で固定する。
- **キャッシュ**（区分 C3 で test_helper に集約する）
  - フラグメントキャッシュは `with_fragment_cache`（`ActionController::Base.cache_store` を差し替える）。
  - `Rails.cache.fetch` は `with_rails_cache`。
- **設定と ENV** は、元の値に戻す `with_config` / `with_env` を使う（区分 C3 で test_helper に集約する）。
- **外部コマンド**
  - 依存するテストは、サービスの `available?` を見て skip する。
  - フォールバックは、`available?` を false にスタブして確かめる。
  - 手本は `test/services/share_card_renderer_test.rb`、`test/controllers/words/share_cards_controller_test.rb`。
- **system テストの操作**
  - JS の接続は `wait_for_stimulus` で待つ。
  - 押し直しても結果が同じ操作は `click_expecting` を使う。
  - 押し直すと困る操作は `click_via_js` を使う。
  - turbo_confirm は `click_accepting_confirm` を使う。
  - キー入力は、JS で keydown イベントを送る。オーナーの運用記録によると、ネイティブのキー入力はヘッドレス Chrome に届かない。
    C3-23 で実行して確かめ、その結果で正典の文面を決める（**要確認**）。
- **canonical ホスト**は、test_helper の定数1つにまとめる（区分 C3 の後）。

### 4.7 文書とコメント

- **事実ごとに正を1か所だけ置き、他の文書からはリンクするだけにする**。

  | 事実 | 正 |
  |---|---|
  | カラム定義 | `db/schema.rb` |
  | 照合順序（何を同一視するか・as_ci の対象） | data-model.md §6 |
  | 派生値（作る場所・再生成・verify） | data-model.md §3 の表 |
  | 合格判定コマンド | CLAUDE.md |
  | デプロイと CI | overview.md（運用の章。G4-03 で新設） |
  | 環境変数 | overview.md §8 |
  | デザインの値と禁止事項 | design.md |
  | ΔRGB の式・ブレークポイントの一覧 | design.md §1・§7（D1-21 で書く） |
  | 統計の図の規則（色の段・操作規則・データの出どころ） | stats.md（JS とヘルパのコメントは節を参照するだけ） |
  | 公開スコープを通らない公開出力の一覧 | data-model.md §8（D1-18 で書く） |
  | 調査の流れ（スキル → 管理画面） | research/README.md |
  | 提案 JSON のキー | `AnnotationProposal` の定数（C3-02 の後）。schema.json と各 SKILL.md はその写しで、冒頭に正の場所を書く |
  | 書き出す調査 JSON の形 | 各 Export クラス（`*Export`）の `as_json` |
  | マスタ名（大分類・中分類・品詞・語種・言語学的特徴） | `SeedCatalog`（genres.md はその写し） |
  | マスタ名（小分類・エンティティ種別） | DB。調査用の書き出しの `masters` が現況 |
  | 言語学的特徴の定義 | 用語解説の YAML（glossary）。注釈スキルの対応表はその写し |
  | 収録基準 | 方針は annotation-guidelines.md §0、値は `WordSense::MIN_READING_LENGTH`。読みの数え方も §0 に書く（D1-19） |
  | 表記の決め方 | annotation-guidelines.md §3 |
  | 読みの表記 | annotation-guidelines.md §4（reading スキルはこれに従う） |
  | 立項スコア | annotation-guidelines.md §2 |
  | 確信度（confidence）の定義 | annotation-guidelines.md（D1-19 で新設） |
  | 語種・ジャンル・エンティティ・言語学的特徴の付け方、意味の文体 | 注釈スキル（word-annotation-research の SKILL.md）（A11-1） |
  | ルート | `config/routes.rb`（画面の役割は overview.md §5） |

- **コメントの扱い**
  - 残すもの: なぜそうしているか、不変条件、外部との約束、長いファイルの区画見出し。
  - 削るもの: 直後のコードを言い換えただけのコメント。
  - 移すもの: 経緯（日付・Issue 番号・計測値・試作の記録）は docs/history か changelog へ移す。
- **参照の書き方**
  - 行番号ではなく、シンボル名と「文書名＋節」で参照する（行番号は必ずずれる）。
  - 件数（「13 条件」など）は文書に書かず、出どころを指す。
  - design.md・stats.md など、コードのコメントが節番号で指している文書は、**既存の節番号を変えない**。
    節を足すときは末尾か小節にし、移すときは欠番にして行き先を 1 行残す（P-02 の PR-5。`§` を含むファイルは app・lib・config・test に 51 ある）。
  - コメントで stats.md の節と統計ページの章を指すときは、「stats.md §N」「統計ページ §N」と書き分ける。
- **コメントに書く数値**（寸法・実測値・割合）
  - 式か出どころ（定数名・文書の節）で書く。
  - 実測値を残すなら、「いつ・何で測ったか」を添える。
  - 「15 層で 818px」（実装の式では 1,148px）や「77%」（いまは 79.6%）のように、数値だけを書いたコメントは、すでに実装とずれている（A01-5・A02-2）。

### 4.8 調査スキルとアプリの境界

調査スキル（`.claude/skills/`・`.claude/commands/`）は、RuboCop とテストの対象外。アプリ側を直しても、スキルが壊れたことに気づけない。

- スキルからアプリのクラスを使うときは、**公開メソッドだけを呼ぶ**。`send` で private を呼ばない。
  - いまは `reading_length.rb` が `ReadingExtractor#normalize`（private）を `send` で呼んでいる（DOC-19）。C3-04 で公開メソッドにする。
  - スキルが呼ぶアプリのメソッドには、「スキル（パス）からも呼ばれる」とコメントを付ける。
- **スキルは規則を写さず、正典の節を参照する**（§4.7 の表）。
  - ガイドラインの本文を SKILL.md に写すと、どちらかだけが直る（A11-12）。
  - 写しが要るとき（対応表など）は、正の場所と「正を直したらここも直す」を書く。
- スキルに DB の現況（小分類・エンティティの名前など）を例として書くときは、日付と「現況は入力の `masters` が正」を添える（A11-11）。
- スキルの文書を直したら、claude.ai 用のスキル束を再生成してアップロードし直す（`tools/claude-ai-skill/build.sh`。オーナーの作業）。

## 5. 改修項目

リスクの目安:
- **低**: 振る舞いに触れない（文書・コメント、参照の無いコードの削除、テストの追加）。
- **中**: 構造は変えるが、出力は同一（特性テストで固定してから行う）。
- **高**: 本番の運用・設定に関わる。この計画には入れていない。

### 区分 T0: 特性テストの追加（テストだけを足す。アプリのコードは変えない）

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| T0-01 | 公開 JSON API のキー集合と入れ子を固定する。対象は詳細・一覧・license。ジャンルの無い語義で `genre` が null になること、`variants` の形も固定する | JSON に触れる集約（C3-16・C3-17）の安全網になる | test/integration/words_api_test.rb | 低 | — | T-01 |
| T0-02 | 外部コマンドのフォールバックを固定する。共有カードは、`fetch` が nil のときと描けない語のときに既定カードへ回る。MeCab が無いとき、ReadingExtractor は nil の配列、MorphemeExtractor は空配列を返す。setup の skip に掛からない別のクラスに書く<br>・「MeCab が無いとき」は、C3-04 で判定をクラスでメモした後も書き換えずに通るよう、PATH を空にして確かめる形で書く（Open3 が ENOENT を投げて退避の分岐に入る。P-02 の PR-16）。 | 「無くても止まらない」の担保。C3-04 の前提 | test/controllers/words/share_cards_controller_test.rb、test/services/reading_extractor_test.rb、test/services/morpheme_extractor_test.rb | 低 | — | T-03、PR-16 |
| T0-03 | 収録リクエストのうち、まだ固定されていない振る舞いを固定する。受付停止中に `/`・`/words`・`/about` から導線が消えること、トークンの期限切れで 422 になること、フォームの項目名 | 公開面で唯一の書き込み経路を守る | test/controllers/word_requests_controller_test.rb | 低 | — | T-04 |
| T0-04 | 公開ページのうち、まだ固定されていない振る舞いを固定する。今日の一語、ホーム検索の `q`、sitemap の `<loc>` の集合、Atom（件数の上限・絞り込みを無視すること・canonical の URL）、ログイン後に元の URL へ戻ること<br>・今日の一語は、キャッシュを有効にし、キャッシュした語数と実際の語数が違う状態でも、キャッシュの語数で選ばれることを確かめる（test 環境は null_store なので、テストの中で局所的に差し替える。P-02 の PR-1）。 | C3-18 の安全網。公開クエリ名 `q` を守る | test/controllers/home_controller_test.rb、sitemaps_controller_test.rb、sessions_controller_test.rb、test/integration/words_feed_test.rb | 低 | — | T-05、PR-1 |
| T0-05 | 多語義語の代表語義と語義の順序を固定する。先頭の語義が最長でない語を使い、ホームの看板・一覧の行・詳細の語義順・JSON の `senses` の順を確かめる | C3-14 の安全網 | words_controller_test.rb、home_controller_test.rb、words_api_test.rb | 低 | — | M-11、C-02 |
| T0-06 | 照合順序の帰結を固定する。表層形の一意制約は、かなの種類・小書きの違いを同一視し、清濁は区別する。`char_type_pattern`（ai_ci）を大小を区別せずに検索すると、あとアを同一視する | D1-03 で文書に書く事実を、テストが担保する | test/models/word_test.rb、word_sense_search_test.rb | 低 | — | CFG-04、M-07 |
| T0-07 | `body.is-admin` の付き方を固定する（管理画面では付き、公開ページとログイン画面では付かない） | C3-06 の安全網 | test/integration/（新規） | 低 | — | S-09、C-18 |
| T0-08 | 検索スライダー（range_slider）の表示文言と hidden の値を固定する（system テスト） | C3-20 の安全網 | test/system/（新規） | 中（system テストは不安定になりやすい） | — | J-07 |
| T0-09 | tokens.css のダークの2ブロック（`@media` と `[data-theme]`）が一致していることと、application.css の読み込み順を静的に確かめる | トークンの足し忘れを検出する。C3-21 の安全網 | test/assets/design_tokens_test.rb | 低 | — | S-08、S-02 |
| T0-10 | 提案の取り込みと反映で捨てられるキーを固定する。<br>・取り込みは、トップレベルの `linguistic_features`・`reading`・`sense_id` を捨てる。<br>・`genre_new` は保持されるが、反映には使われない。<br>・`target_start` は反映で使われず、特徴は先頭の出現に付く。 | C3-02 の安全網（`legacy_sense_hash` の `reading` を消す前提を固める） | test/models/annotation_proposal_import_test.rb、test/models/proposal_application_test.rb | 低 | — | M-05、A08-1〜A08-3 |
| T0-11 | `backfill:sense_metrics` が、崩した代表値を元に戻すことを固定する | C3-12 の安全網 | test/tasks/backfill_task_test.rb | 低 | — | T-06、CFG-02 |
| T0-12 | 名前と中身がずれているテストを直す。テスト名を中身に合わせ、名前が約束していた検証は新しいテストとして足す（単語を消すと特徴も消える、同じ該当部分の特徴を別の語義に付けられる）。既存の assert は変えない | テスト名を信じた誤認を防ぐ | test/controllers/admin/words_controller_test.rb、test/models/word_sense_feature_test.rb、reannotation_export_test.rb | 低 | — | T-12 |
| T0-13 | 読みを変えて保存すると `words.reading_density` が追従することを固定する（いまは語義の作成時と表層形の更新時しか確かめていない） | STORED 列が after_commit の値に依存していること（M-02）の安全網。C3-12・D1-04 の前提 | test/models/word_sense_metrics_test.rb | 低 | — | M-02（棚卸し B-01） |
| T0-14 | 母音遷移の境界値を固定する。`vowel_transition` の受理と棄却（15 拍・位置 30 / 31）と、`SiteStatistics` が出す層の上限 15 | C3-01 で正規表現の上限を定数から組む前提 | test/models/word_sense_search_test.rb、test/models/site_statistics_test.rb | 低 | — | A05-4 |
| T0-15 | og:image の版を固定する。フィクスチャの語（`abc_murder` など）の `WordShareCard#digest`（共有カードの SVG 全体の SHA256）を、文字列で固定する（改修のあいだの特性テスト。残すかどうかは G4-05 で決める） | §0.2 で守ると宣言した og:image の安全網。SVG の入力（代表語義・円環の点・標識のドメイン・テンプレート）に触れる C3-09・C3-14・C3-15・C3-16 の前提 | test/models/word_share_card_test.rb | 低 | — | PR-6 |
| T0-16 | 一括登録の調査 JSON で、形が不正な入力（Hash でない要素・空の入力）の現在の扱いを固定する | C3-03 の前提 | test/models/bulk_word_registration_test.rb | 低 | — | M-12、PR-15 |
| T0-17 | 公開一覧のページ送り（seed の引き継ぎ・nofollow）を固定する | C3-08 の前提 | test/controllers/words_controller_test.rb | 低 | — | C-09、PR-15 |
| T0-18 | かなの畳み込みの各呼び出し元で、半角カナ・合成濁点・ゔ・ゕゖ を含む入力の現在の出力を固定する | C3-15 の前提（RhythmPattern・MoraCount は保存済みの派生値に関わる） | test/models の該当ファイル、test/helpers/words_helper_test.rb、test/services/reading_extractor_test.rb | 低 | — | M-04、PR-15 |
| T0-19 | 管理一覧のジャンル絞り込み（配下まで広げる処理）の現在の結果を固定する | C3-18 の前提 | test/controllers/admin/words_controller_test.rb | 低 | — | C-11、PR-15 |
| T0-20 | publish_guard と deck が、削除済みの語義を数えないことを固定する（system テスト） | C3-19 の前提 | test/system の該当ファイル | 中（system テストは不安定になりやすい） | — | J-05、PR-15 |
| T0-21 | `WordSense::JAPANESE_ORIGIN_NAME` が SeedCatalog の語種名に含まれることを確かめる | C3-01 で定数の参照先を変える前の安全網（語種名を改名すると `with_japanese_origin` が黙って 0 件を返す） | test/models/seed_catalog_test.rb | 低 | — | CFG-07、PR-15 |

### 区分 D1: 文書・コメントの矛盾解消（嘘を消す。振る舞いは変えない）

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| D1-01 | **デプロイと CI の実態を書く**。<br>・main への merge（push）で deploy.yml が本番へ自動デプロイし、CI の完了を待たない。<br>・seed は `deploy:migrate` の直後に毎回走り、マスタの改名（`*_RENAMES`）も行う。<br>・本番の DB 接続はサーバ上の database.yml が持つ（リポジトリの production ブロックと deploy.rb の `default_env` は使われていない）。<br>書く場所: CLAUDE.md（厳守事項に1行）、overview.md の §2 と §8、cppmtm.md の merge 手順への注記、config/deploy.rb の desc、使われていない設定へのコメント、deploy.yml の冒頭のコメント（インフラ設定のファイルだが、変えるのはコメントだけ）<br>・完了条件: `bundle exec cap -T`（SSH に接続しない）が通ること。deploy.yml と database.yml が YAML として読めること（P-02 の PR-14）。 | エージェントが merge の重さを誤解しなくなる | CLAUDE.md、docs/overview.md、.claude/commands/cppmtm.md、config/deploy.rb、config/database.yml、.github/workflows/deploy.yml | 低 | — | DOC-01、CFG-01、CFG-05、PR-14 |
| D1-02 | **合格判定コマンドを、動く形に直す**。<br>・CLAUDE.md・overview §9・cppmtm.md を、`bin/rails test` と `bin/rails test:system` の2本（または CI と同じ `bin/rails db:test:prepare test test:system`）にする。<br>・WSL で要る環境変数の名前（CHROME_BIN、必要なら LD_LIBRARY_PATH）を書く。<br>・eager load は CI=1 のときだけ効くことを書く。<br>・「ローカルで通れば CI も通る」を訂正する。<br>・README.md の連結形も直す（初版では §7.6 に回していた）。 | 最初の一手で「テストが壊れている」と誤診しなくなる | CLAUDE.md、docs/overview.md、.claude/commands/cppmtm.md、README.md | 低 | — | DOC-02、CFG-09 |
| D1-03 | **照合順序の記述を、§1 の実測に合わせる**。<br>・CLAUDE.md の as_ci 一覧には word_candidates が無い。一覧は data-model §6 だけに置き、CLAUDE.md からは参照するだけにする。<br>・data-model §6 に次を足す: 小書き・全角と半角も同一視されること、一意制約にも同じ同一視が効くこと、`word_sense_features.target` / `target_reading` は ai_ci のままであること、`char_type_pattern` は ai_ci であること、マスタ名の一意制約は ai_ci であること（清濁だけが違う名前は作れない）。<br>・word_sense_metrics.rb と data-model §5 にある「清濁が畳まれて」を訂正する。<br>・`char_type_pattern_matching` のコメントに「あ＝ア」を補う。 | 照合順序を「直す」誤った変更を防ぐ | CLAUDE.md、docs/data-model.md、app/models/word_sense_metrics.rb、app/models/word_sense.rb | 低 | T0-06（テストは後でもよい。事実は §1 で実測済み） | DOC-04、CFG-03、CFG-04、M-07、M-16 |
| D1-04 | **派生値の一覧と直し方を、1つの表にまとめる**。<br>・data-model §3 に「カラム／作る場所／再生成するタスク／verify の対象か／依存する派生値」の表を置き、CLAUDE.md からは参照するだけにする。<br>・STORED の reading_density が max_reading_length に依存することを明記する。<br>・**C3-12 と同じコミット群で行う**（backfill の対象が変わるため）。 | 派生値の出どころを1か所で辿れる | docs/data-model.md、CLAUDE.md | 低 | C3-12 と同時 | DOC-05、M-02、CFG-02 |
| D1-05 | **CLAUDE.md の規約文を、差分を最小にして実態に合わせる**（全体の再編は G4-01 で行う）。<br>・認証: 全アクションが既定で認証必須で、公開側は `allow_unauthenticated_access` で外す。「書き込み系に before_action を付ける」は実態と違う。<br>・ジョブ: 1本も無い。重い処理（共有カード・代表値の UPDATE・MeCab）は意図して同期で実行している。<br>・system テスト: 「JS が無いと成立しない挙動だけ」を「実ブラウザが要る挙動だけ」に直す。<br>・管理画面の未ログイン拒否は、admin_authentication_test がまとめて検証していることを書く。<br>・README の技術スタックの表にある、ジョブの行（ActiveJob の `:async` アダプタ）も、ジョブが 1 本も無いことに合わせて直す（DOC-17）。 | 不要な before_action の追加や、共有カードの非同期化といった「規約どおりの改悪」を防ぐ | CLAUDE.md、README.md | 低 | — | DOC-09、T-10、T-02、DOC-17 |
| D1-06 | **調査スキルと調査手順の「この後の流れ」を、現行のフローに合わせる**。<br>・収穫・表記・読みの各スキルは、「上部リストをそのまま notation.txt へ」「重複は登録 step3 が弾く」という旧フローを案内している。<br>・流れの単一の出典を research/README.md にし、各 SKILL からは参照するだけにする。<br>・annotation SKILL が参照する公開 API のホストを www なしにする。<br>・annotation-guidelines の「運用」の節を直す。<br>・ja.yml の取り込み欄のプレースホルダ（旧形式）を senses 形式にする。<br>・annotation SKILL を直したら、claude.ai 用のスキル束の再生成（tools/claude-ai-skill/build.sh）と再アップロードが要る（オーナーの作業）。<br>・word-expansion-research の SKILL.md と expand.md にも、同じ旧フロー（「重複は登録 step3 が弾く」「上部リストはそのまま /notation へ」）が残っているので直す（DOC-20。初版では §7.6 に回していた）。<br>・research/README の /expand の説明「種語と同じエンティティ軸で集める」を、スキルの実際（読み 10 文字以上が見込める軸を 1 つ選ぶ。種語の軸とは限らない）に合わせる（A11-10）。<br>・規則（収録基準・表記・読み・特徴の付け方）の食い違いは D1-19、提案 JSON の取り決めは D1-20 で直す。同じファイルに触れるので、D1-06 → D1-19 → D1-20 の順に 1 本ずつ行う。 | ID が落ちて取り込みで全件が見送られる事故を防ぐ | .claude/skills/word-{harvest,notation,reading,annotation,expansion}-research/SKILL.md、.claude/commands/expand.md、research/README.md、docs/annotation-guidelines.md、config/locales/ja.yml | 低 | — | DOC-03、DOC-10、DOC-14、DOC-20、A11-10 |
| D1-07 | **文書間の参照切れと、置き場所の食い違いを直す**。<br>・CLAUDE.md の「issues.md Issue 80・81」と data-model の「Issue 56」の参照先を changelog.md に直す。<br>・issues.md の docs/improvements.md（一度もコミットされていない）に注記する。<br>・issues.md の行番号による参照（word_sense.rb:251-258）をシンボル名にする。<br>・issues.md の importmap の pin についての記述を直す。<br>・overview の「完了記録は issues.md」を changelog.md に直す。<br>・changelog に #162〜#164 を追記する。<br>・.gitignore のスキル名の列挙を直す。 | 案内に従って辿ると行き止まりになる箇所を無くす | CLAUDE.md、docs/data-model.md、docs/issues.md、docs/overview.md、docs/changelog.md、.gitignore | 低 | — | SPEC-14、DOC-15、CFG-11、SPEC-12、DOC-16 |
| D1-08 | **否決・失効した判断を今も指示している記述を直す**。<br>・growth-strategy の優先順位: 特徴の遡及付与は確定事項37で却下、Bing は確定事項33で当面触らない。<br>・issues.md の確定事項16・18（朱・墨）に、失効したことを注記する。<br>・performance-report の冒頭に「§8 の現状は issues.md」と書く。<br>・stats.md の「最頻のみ --chart」を直す。<br>・「fragment cache」を「集計キャッシュ」にする。<br>・growth-strategy の「文言は home.index.* から派生」の誤りを直す。 | 却下された作業に着手するのを防ぐ | docs/growth-strategy.md、docs/issues.md、docs/performance-report.md、docs/stats.md、docs/changelog.md | 低 | — | SPEC-01、SPEC-10、SPEC-11、SPEC-16、SPEC-21、SPEC-23 |
| D1-09 | **design.md（と CLAUDE.md のデザイン節）を、CSS の実態に合わせる**。実装（後から実測して決めた値）を正とし、見た目は変えない。直す記述:<br>・ゼロ埋めの例外（一覧の目盛り `.entry-range` の 001–100 だけ）<br>・`--bg` の実際の用途と面の段<br>・章の罫は `.sheet` を含めて5箇所<br>・管理画面は、トークンに加えて一部のコンポーネントも上書きし、管理用の2色（`--admin-accent` / `--admin-warn`）を持つ<br>・行間 1.75、見出し 24px（/search だけ 21px）、ヒーロー 26px、10px の例外<br>・区切り線と囲い（sense-card / rank-board）の記述<br>・§5.3 の中の矛盾（行に角丸を持たせない／当たり判定の角丸）<br>・動きの例外（状態の変化に伴う transition と状態ラベル）<br>・検索条件の数（「13」と書かれているが、Issue 92 で区画が増えている。数は書かずに出どころを指す）<br>・Issue 84 と実測値についての古い記述<br>・管理画面はダークに対応していないという事実（§7.5）<br>・節を足すときは末尾か小節にし、既存の節番号は変えない（§4.7）。完了条件: `design.md §` の参照先がすべて実在すること（P-02 の PR-5）。 | 同じ文書のどの節を正とするかで、変更の向きが逆になる事態を防ぐ | docs/design.md、CLAUDE.md | 低 | — | SPEC-02〜06、S-13、J-12、DOC-08、S-01、PR-5 |
| D1-10 | **stats.md を実装に合わせる**。<br>・図のリンク先は /words（/search ではない）。<br>・紙面の順序を直す。<br>・章題に画面の見出し（ja.yml のキー）を併記する。<br>・未実装のキャプションを直す。<br>・文書の節番号と紙面の章番号が衝突している。文書の節番号は変えずに（§4.7）、コメントでの参照を「stats.md §N」（文書の節）と「統計ページ §N」（紙面の章）に書き分ける。完了条件: `grep -rn '§[0-9]' app lib config test` の結果をすべて確かめ、どちらを指すかが読み取れること（P-02 の PR-5）。<br>・補完監査 A-01・A-02・A-05 の分（実装を正とする）:<br>　- §7 の「拍位置」は `vowel_pattern` の添字（何番目の母音か。撥音・促音を数えない）で、`mora_count` の拍とは別だと書く（A01-3。画面の文言を変えるのは §7.1）。<br>　- 「明度差で識別する」5 段の塗り分けを事実に合わせる。明度は 4 段で、3 位と「その他」は色相で分かれる（A05-2。配色を変えるのは §7.4）。<br>　- 地を `--bg` で塗っている箇所があること（本文の地は `--surface`）と、チントの式が 3 通りあることを書く（A05-3）。<br>　- §7 の操作規則を「選んだ鎖」の記述に改め、実装にある「控えだけ外す」を足す（A05-7）。<br>　- §4・§7 のデータの出どころを実装に合わせる。推移は Ruby で週単位に数え、点は末尾だけに打つ。スペクトルは `vowel_pattern` だけを使い、1 割で打ち切って最大 24。頭子音は頭文字から出す（A05-8）。<br>　- §8 の件数の単位（該当部分ごと）を書く（A05-11）。<br>　- ワードクラウドの経緯の数値（60 件中 24 件など）を、コメントからこの文書へ移す（A02-2）。 | noindex の URL を増やす誤りを防ぐ。画面の文言から節に辿れるようにする | docs/stats.md、app/helpers/stats_helper.rb、app/models/site_statistics.rb、app/models/morpheme_cloud.rb、app/assets/stylesheets/components.css（参照コメント）、§N で参照しているファイル（app/views/stats の 7 パーシャル、panel_switch・vowel_graph のコントローラ、tokens.css、morpheme_extractor.rb・word_sense.rb・morpheme_frequencies.rb・word_sense_search.rb、lib/tasks/stats.rake など） | 低 | — | SPEC-09、SPEC-17、A01-3、A02-2、A05-2、A05-3、A05-7、A05-8、A05-11、PR-5 |
| D1-11 | **genres.md と SeedCatalog の関係を直す**。<br>・正は SeedCatalog で、genres.md はその写し（Issue 85 で生成物にする予定）。<br>・seed_catalog.rb の「出典: docs/genres.md」と、存在しない RENAMES という定数名を直す。<br>・genres.md に書かれた小分類の追加経路を直す。タグ管理では追加できず、実際の経路はピッカー・一括注釈・提案の新設候補の3つ。 | genres.md を先に直して seed に反映されない、という逆向きの変更を防ぐ | docs/genres.md、app/models/seed_catalog.rb | 低 | — | DOC-06、SPEC-08 |
| D1-12 | **モデル・サービスのコメントを実装に合わせる**。<br>・`Word.unannotated` の説明を「注釈済み」から「未注釈」に直す。<br>・word.rb の「annotated / published スコープ」（Word には published が無い）。語と語義で公開条件の名前が違うことを書く。<br>・ProposalApplication の「保存しない」（`persist: true` のときは中間表に書く）。<br>・WordRequestDuplicateCheck の far_apart?。<br>・KanaRow の用途（ring_crossing_count に波及する）。<br>・SiteStatistics の冒頭と「タグクラウド」。<br>・語種名（和語／漢語。正しくは「日本語」）。<br>・bulk_word_registration の「将来の差し込み口」。<br>・word_sense_metrics.rb の「テストと backfill から参照」。<br>・`WordCandidate::DECISIONS` への参照を `WordCandidateReview::CHOICES` にする。<br>・クラス冒頭の種別ラベルを 4.1 の語彙に揃える。<br>・重複チェックの3実装の違いが意図であることを書く。<br>・テストからしか使わないメソッドに「テスト用」と注記する。<br>・補完監査 A-02 の分（MorphemeCloud・MorphemeFrequencies・ShareCardTypesetter・WordShareCard）:<br>　- 「最後の結果をそのまま返す」を、1 段広げた高さで詰め直して返すこと、枠より広い語は落ちることに直す（A02-1）。<br>　- ある時点の集計に縛られた実測値に、出どころ（いつ・何で）を添える（A02-2）。用語の揺れと小さな食い違いを直す（A02-3）。<br>　- 欧文の幅表の `Z` と記号が実測より狭いことを注記する（A02-4。値を変えるのは §7.4）。`Placed#top` はテスト用だと注記する（A02-6）。<br>　- 字幅の見積もりが 2 系統あることを、両方のメソッドに相互参照で書く（A02-7。統合は §7.7）。<br>　- ShareCardTypesetter の「割りやすい所」を実装に合わせる（A02-8）。字幅は Noto Sans CJK JP が前提だと書く（A02-9）。<br>　- MorphemeFrequencies が、壊れた JSON を空として扱い、読めないファイルでは例外にすることを、方針として 1 行書く（A02-10）。<br>・補完監査 A-01・A-06・A-08 の分:<br>　- `SiteStatistics` の「拍位置」が何番目の母音かであること（A01-3）。<br>　- `ProposedMasterCreation` の冒頭を、語種は呼び出し側が渡した名前で作る、という事実に直す（A06-6）。`SeedCatalog.seeded?` は完全一致で判定すると書く（A06-4）。<br>　- `ProposalApplication` の冒頭に、項目ごとの反映の意味（上書き／置換／追加のみ）を表で書く（A08-5）。<br>　- `SiteStatistics` の母音スペクトルと特徴ランキングの `total` は、画面では使わず、テストだけが参照していると注記する（P-02 の PR-3）。 | 名前やコメントから逆の意味を読み取る誤りを防ぐ | app/models の該当ファイル | 低 | — | M-03、M-06、M-15、M-16、C-12、SPEC-15、SPEC-16、DOC-16、CFG-07、A01-3、A02-1〜A02-4、A02-6〜A02-10、A06-4、A06-6、A08-5、PR-3 |
| D1-13 | **暗黙の前提をコードに書く**。<br>・update_all でタグを統合する経路（genre / entity_type / part_of_speech）と annotations_controller の update_all は、touch と after_commit を通らない。<br>・RefreshesWordMetrics は全ての commit で発火し、冪等である。<br>・WordCandidateExpansionImport は、トランザクション内で RecordNotUnique を捕まえて続行している（MySQL に依存）。<br>・JAPANESE_ORIGIN_NAME は SeedCatalog の語種名に依存している。<br>・プロセス内のメモは再起動まで有効（glossary、形態素頻度、ShareCardRenderer.available?）。<br>・収録基準はモデルでは検証せず、登録時の UI で当てている。<br>・Candidates::BaseController#run_import の前提。<br>・公開状態を annotated_at と annotation_status の2列で持っている。<br>・補完監査の分:<br>　- `WordSenseFeature` の `target_start` は `surface[target_start, target.length] == target` を前提にしているが、どこも検証していない（A01-1。検証を足すのは §7.1）。<br>　- マスタ名の正規化（前後の空白の除去）はその場追加にしか無く、衝突したときの扱いは経路ごとに違う。各経路に、他の経路との違いを書く（A06-1・A06-2。揃えるのは §7.1）。<br>　- 提案の新設候補と seed は、競合を `find_or_create_by!`（Rails 8.1 では `create_or_find_by!` を経由）に吸収させている（A06-3）。<br>　- `entry_score` の範囲外の値を、Ruby は未評価、SQL（`needs_review`）は要判断として扱う（A08-8）。<br>　- 不完全な特徴・別表記は、取り込み後に `SenseProposal` が黙って除外する（A08-6。知らせるようにするのは §7.1）。<br>　- `WordBatch` は、公開語の id だけを預かる前提で動く（A09-3）。 | 変更の影響範囲をコードから辿れる | app/models・app/controllers の該当ファイル | 低 | — | M-08、M-13、M-18、M-20、M-21、SPEC-13、CFG-07、A01-1、A06-1〜A06-3、A08-6、A08-8、A09-3 |
| D1-14 | **コントローラ・ビュー・ヘルパのコメントを実装に合わせる**。<br>・home_controller の「words#feed」「新着より上」。<br>・home/index の重複コメント、words/index のファセット一覧。<br>・genres/index の「ホームと同じ定義」（実際は3通り。§7.5）。<br>・「単語一覧は public でキャッシュ」（public なのは詳細と Atom）。<br>・「太字」「アクセント」「印章」のコメント。<br>・stats_helper の「2周期」、_sound_matrix の「10×11」、_entry_row の組み方、words/show が参照する design.md の § 番号。<br>・searches_controller の許可パラメータ（words_controller と集合が違うことを明記する。§7.1）。<br>・レイアウトは CSP が未設定であることを前提にしている。<br>・テーマの復元処理2か所に、相互参照を書く。<br>・theme-color の既定値についてのコメント。<br>・補完監査の分:<br>　- 統計の分布の最頻値を、ヘルパと `SiteStatistics` が別々に求めていること、両者が食い違う条件（A01-4。揃えるのは §7.1）。<br>　- stats_helper の「15 層で 818px」（実装の式では 1,148px）、「色・線種は CSS に任せる」、「CSS の縦横比と一致させる」（A01-5）。<br>　- 統計の横棒と「最多の色」が「先頭行＝最多」という並びに頼っていること（A05-10）。`top` というキーが 3 つの意味で使われていること（A05-9。改名は §7.7）。<br>　- `_kana_ring_art` の「キャプションの 2 行目に必ず値」を、D1-21 で決める規則（図のキャプションは標識の規則の対象外）に合わせる（A05-5）。<br>　- 同じ円環を描く 3 テンプレート（`_kana_ring_art`・`_brand_mark`・共有カードの SVG）の互いの場所を、`_kana_ring_art`・`_brand_mark` と `WordShareCard` に書く（A05-6。描画をまとめるのは §7.7）。**共有カードの `share_cards/word.svg.erb` には触れない**（ERB のコメント行の間の空行も出力に入る。SVG のバイト列が変わると og:image の URL が変わる。P-02 の PR-6）。<br>　- 登録予定単語の「元の語」「系統の子」の判定が 3 通りあることと、その違い（A04-6。揃えるのは §7.1）。<br>　- 提案パネルの「特徴にはその場追加が要る」というコメントと、新設候補が失敗したときの案内（ja.yml）。実際は、特徴はタグ統括管理で足し、それ以外はコンソールのその場追加で足す（A06-5）。<br>　- レイアウトに残る、撤去済みのフッターのワードマークのコメント（A10-7）。 | 古い設計の語彙で誤読するのを防ぐ | app/controllers・app/views・app/helpers の該当ファイル、config/locales/ja.yml（A06-5 の案内） | 低 | — | SPEC-15、SPEC-07、C-23、C-01、C-03、J-11、S-08、C-22、A01-4、A01-5、A04-6、A05-5、A05-6、A05-9、A05-10、A06-5、A10-7、PR-6 |
| D1-15 | **JavaScript のコメントを実装に合わせる**。<br>・importmap.rb と controllers/index.js の「公開ページではコントローラを使わない」（ヘッダーの3本は全ページで使う）。<br>・nav_drawer の「検索パネル」、char_type のキーの数、auto_submit の「親フォーム」、check_all の用途、queue_nav が先頭へスクロールすること。<br>・range_slider・feature_range の「アクセント」。<br>・genre_sunburst の「色は JS に持たせない」と直書きのパレットの矛盾、`--bg` を地と呼んでいる箇所。<br>・controllers/application.js の window.Stimulus はシステムテストに要ること。<br>・sense_cloner は Rails の nested attributes の名前に依存していること。<br>・js-genre-* はテスト用のフックであること。<br>・サーバ側の規則を JS も持っている箇所（どちらが正か）。<br>・Plotly を意図してピンしないこと。<br>・feature_range の `restoreOne` が `target_start` の前提に頼っていること。数え方の正は `word_sense_feature.rb` と schema.rb のコメントにある（A01-1）。<br>・vowel_graph の操作規則は、stats.md §7 を参照するだけにする。線の最大幅 3.2 が `StatsHelper::GRAPH_MAX_EDGE` と同じ値であることも書く（A05-7・A05-4）。 | 「公開側は JS 無し」などの誤読を防ぐ | config/importmap.rb、app/javascript/controllers の該当ファイル、app/assets/config/manifest.js | 低 | — | J-01、J-06、J-08、J-09、J-16、J-18、J-19、J-20、CFG-10、A01-1、A05-4、A05-7 |
| D1-16 | **CSS のコメントを実装に合わせる**。<br>・tokens.css の冒頭を 4.4 の方針にし、「画像帯」「構造は余白で作る」を直す。<br>・base.css の対象（`.mono` を含む）と「ヘッダー(--bg)」。<br>・application.css の冒頭に実際の配置を書く（candidates.css の役割、管理用の CSS も全ページで読まれること、読み込み順の意味）。<br>・components.css の古いコメント（「唯一」「4 箇所」「001–050」など。SPEC-15・S-12 に列挙）。<br>・admin.css の冒頭の方針と実測値。<br>・annotate.css の「青一色」「枠を緑に」、layout.css の「縦の基準線」。<br>・i18n の中にあるクラス名（shiritori__char・cand-export__num）の使用元。<br>・読み込み順に依存する規則の両側に注記する。<br>・補完監査の分:<br>　- 統計の §6・§7 の CSS で地を `--bg` で塗っているのは、旧い「地」の名残であること。本文の地は `--surface`（A05-3）。<br>　- 母音遷移の線の最大幅 `stroke-width: 3.2` が `StatsHelper::GRAPH_MAX_EDGE` と同じ値であること（A05-4）。<br>　- 補間で組み立てる修飾子のうち、既定の見た目に任せる値（CSS を持たない値）の列挙（A07-4。§4.4）。<br>　- 見た目用のクラスを JS・テストも参照している箇所の注記（A07-5。§4.3）。 | 置き場所と方針を誤読するのを防ぐ | app/assets/stylesheets の全ファイル | 低 | — | S-02、S-03、S-07、S-10、S-12、SPEC-03〜05、SPEC-15、A05-3、A05-4、A07-4、A07-5 |
| D1-17 | **設定・タスク・テストのコメントを実装に合わせる**。<br>・application.rb の INDEXING_ENABLED（解禁済み。値は見ず、設定されているかどうかで決まる）。<br>・puma.rb に理由を書く（preload_app! の分岐、ソケットのパスと deploy_to、worker_timeout）。<br>・routes.rb に公開と管理の見出しを付け、公開 URL とクエリ名は変えないことを書く。apply_research も説明に加える。<br>・stats.rake の「本番に MeCab が無い」前提を overview の外部コマンドの表へ移す。backfill.rake の冒頭を直す。<br>・db/migrate のコメントは当時の記録で、現行の正は schema.rb であることを data-model に1段落書く。<br>・テスト側:<br>　- application_system_test_case の Google Fonts（アプリはもう web フォントを読まない。遮断を外部通信を塞ぐ保険として残すなら、そう書く。T-20）と「sticky ヘッダー」<br>　- backfill_task_test の「ずれは検出される」<br>　- 管理画面のテストに残る空の見出し5つと、word_requests テストのファイル説明<br>　- fixtures/word_senses.yml の murder の読みがひらがなである意図<br>　- システムテストの入力手段についての、互いに矛盾するコメント（**要確認**: 実行して現状を確かめてから、1か所にまとめて書く）<br>　- morpheme_frequencies_test の失敗メッセージの「朱」<br>・stats.rake の「冪等」（生成日時が毎回変わるので、ファイルは同一にならない。A02-3）と、`SURFACES_FILE` には公開語だけのファイルを渡すこと（A09-2）。 | 環境や設定についての誤った知識が引き継がれるのを防ぐ | config/application.rb、config/puma.rb、config/routes.rb、lib/tasks/*.rake、docs/data-model.md、docs/overview.md、test の該当ファイル | 低 | — | CFG-08、CFG-15〜18、DOC-13、DOC-16、T-02、T-06、T-09、T-19、J-18、SPEC-16、T-20、A02-3、A09-2 |
| D1-18 | **公開スコープの例外を、data-model §8 に表で書く**。<br>・§8 の「一覧・検索・sitemap・API・統計のすべてがこのスコープを通る」には、書かれていない例外が 3 つある。どれも語の漏れではない理由を添えて表にする（A09-2）。<br>　- 統計のワードクラウドは、コミット済みの事前集計ファイルを読む。<br>　- /search のフォームとファセットの見出しは、マスタを全件出す。<br>　- ホームの「ジャンル数」は、マスタの件数（C-08）。<br>・公開の取り消し（保留・削除）がキャッシュに最大 1 日残ることをオーナーが許容した場合は、そのことを §8 と `published_words_digest.rb` の冒頭に書く（A09-1。§7.5 の回答による）。 | 「すべて通る」を信じて、例外の経路を見落とすのを防ぐ | docs/data-model.md、app/controllers/concerns/published_words_digest.rb | 低 | — | A09-1、A09-2 |
| D1-19 | **収録基準ガイドラインと調査スキルの食い違いを直す**（§4.7 の正典表と §4.8 に従う）。<br>・正の所在: 語種・ジャンル・エンティティ・言語学的特徴の付け方は注釈スキルが正だと、README・ガイドライン・再注釈スキルに書く。再注釈スキルの「立項スコアの定義は注釈スキル」を「ガイドライン §2」に直す（A11-1）。<br>・ガイドライン §0 に読みの数え方（カタカナの読みの文字数。`word_senses.reading_length` と同じ）を書く。/harvest の「モーラ」と判定の委ね先を直し、例の「メイショウタバル」（8 文字）を差し替える（A11-3）。<br>・注釈スキルの手順 1 に、語義を足すときの読みも §0・§4 に従うことを足す（A11-4）。手順 9 の表記の確定を、ガイドライン §3 の参照にする（A11-6）。<br>・別表記の類型を §3.3 に合わせる（「冠称付きの正式名」の言い換えと、旧称の追加。A11-7）。<br>・特徴の対応表に 3 行を足す（畳語（漢字語を含む）、オノマトペ 2 種を正式名で、ゴママヨ）。「対応表に無い」を「glossary に無い」に改める。seed_catalog の注記に「glossary に特徴を足したら対応表も直す」を並べる（A11-8）。<br>・熟字訓の例を glossary の定義（訓読みに限る）に合わせて差し替え、特殊読みの例は `target_reading` の値ではないと注記する（A11-9。glossary の定義を広げたい場合は §7.5）。<br>・「マスタに無い言語」の例を、カタログに無い言語に替える。小分類・エンティティの列挙に、日付と「現況は入力の `masters` が正」を添える（A11-11）。<br>・ガイドライン §2・§4・§6 の写しを、参照 1 行に置き換える。§4 とスキルが互いを正と指し合っているのを、「reading スキルは §4 に従う」に直す。用語を「言語学的特徴」に揃える（A11-12）。<br>・確信度（confidence）の定義をガイドラインに 1 か所置き、注釈スキルの中の 2 通りの条件をそれに揃える（A11-13）。<br>・特徴の `target_reading` は、入力の `reading` から字種も含めてそのまま切り出す、と書く（A11-2。開発用 DB にひらがなの読みは 0 件なので、読みの正規化は §7.2）。<br>・/harvest の「発表直後の公式名称は慣用性を満たす」とガイドラインの食い違いは、オーナーの判断（§7.5・A11-5）に合わせて、どちらかを直す。<br>・直したら、claude.ai 用のスキル束を再生成する（オーナーの作業）。 | 調査の結果が、どの文書を読んだかでぶれるのを防ぐ | docs/annotation-guidelines.md、.claude/skills/word-{annotation,reannotation,reading,notation,expansion,harvest}-research/SKILL.md、.claude/commands の対応ファイル、research/README.md、app/models/seed_catalog.rb（コメント） | 低 | — | A11-1〜A11-13 |
| D1-20 | **提案 JSON の取り決めを、スキルの文書と schema.json に事実どおりに書く**（アプリの振る舞いは変えない）。<br>・`genre_new` は参考情報で、取り込み側は名前で判定する、と書く（A08-2）。<br>・`target_start` は現状では反映で使われず、特徴は先頭の出現に付く、と書く（A08-3。使うようにするのは §7.1）。<br>・schema.json に `required` を書く（提案の `entry_score`・`senses`、語義の必須 4 項目。条件付き必須は `if` / `then`）。example.json の word_id 125（`senses` が無い）は、取り込みが `senses` の無い提案を受け付けるかを確かめてから、SKILL.md に省略できる条件を書くか、例を直す（A08-4。**要確認**）。<br>・再注釈スキルに、特徴・別表記を外す結論は JSON では伝わらない（反映は足すだけ）ことと、`notes` に書いて伝える手順を足す。「取り込み側で検証」を「保存時に検証」に直す（A08-5）。<br>・特徴だけの再調査の書き出しを残す場合は、単一語義の語だけ正しく反映され、既存の提案は上書きされる、と ja.yml の説明と `feature_research_export.rb` に書く（A08-10。残すかどうかは §7.5）。 | スキルが「書けば使われる」と信じて出したキーが、黙って捨てられる事態を防ぐ | .claude/skills/word-annotation-research/（SKILL.md・schema.json・example.json）、.claude/skills/word-reannotation-research/SKILL.md、app/models/feature_research_export.rb、config/locales/ja.yml | 低 | — | A08-2〜A08-5、A08-10 |
| D1-21 | **design.md を実装に合わせる（補完監査の分）**。D1-09 と同じく、実装を正として文書を直し、見た目は変えない。<br>・ΔRGB の式を §1 で 1 つに定義し、テストとコメントからそれを参照する（式はオーナーの判断による。§7.5・A10-1）。<br>・§6 のタップ領域: 実際の寸法（`.btn` 40px、タグ約 29px、フッターのリンク約 25px）を書き、44px を満たすのは管理画面の行選択だけだと書く（A10-2。44px に揃えるのは §7.4）。<br>・§10.1.3 に「管理一覧の行の hover では、状態の色が AA を割る（未対応）」と書く（A10-3。直すのは §7.4）。<br>・§7: 「モバイルファースト」を「広い幅が基底で、狭い幅を max-width で上書きする」に直す。ブレークポイントの表（幅・役割・代表の箇所）と、表を畳むか横スクロールさせるかの選び方を足し、検証幅に 1000px 前後を加える（A10-5・A10-6）。<br>・§5.1: フッターの説明から撤去済みのワードマークを消す（A10-7）。「フッターの幅と余白はヘッダーと同値」に「560px 以下の左右の余白を除く」を添える（A10-8。揃えるのは §7.4）。<br>・§5.8: フッター最下段の `EST. 2026 / JAPAN` が標識の規則の例外であることと、図のキャプションは標識の規則の対象外であることを書く。CLAUDE.md の標識の行に「例外は design.md §5.8」を添える（A10-9・A05-5）。<br>・入力の focus の説明に、共通の `:focus-visible` のアウトラインも出ることを足す（A10-10）。<br>・共有カードの「割りやすい所」の説明を、ShareCardTypesetter の実装に合わせる（A02-8）。<br>・クラス名の付け方（§4.4 の規則）を書く（A07-3）。<br>・閉じたドロワーがフォーカスを受けること、ナビのランドマークで名前を持つのが 1 つだけなことを、既知の問題として書く（A10-4・A10-11。直すのは §7.1）。<br>・節を足すときは末尾か小節にし、既存の節番号は変えない（§4.7）。完了条件: `design.md §` の参照先がすべて実在すること（PR-5）。 | UI を変えるときに最初に読む文書が、実装と食い違わないようにする | docs/design.md、CLAUDE.md（1 行） | 低 | — | A10-1〜A10-11、A02-8、A05-5、A07-3、PR-5 |

### 区分 R2: 残骸の削除

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| R2-01 | 使われていない Ruby コードを消す。<br>・`app/helpers/articles_helper.rb`（scaffold の残り）<br>・`BulkWordRegistration::MergedEntry#match?` / `#differ?`<br>・`WordCandidate::DECISIONS`（コメントからしか参照されていない）<br>・`test/test_helpers/session_test_helper.rb` の `sign_out`<br>テストからしか使われていないメソッドは消さず、注記する（D1-12）<br>・`MorphemeCloud` の `Placed` の `weight` と、`Layout#any?`、`MorphemeFrequencies.metadata`（A02-6。集計日を表示したくなったら足し直す）<br>・統計の使われていない戻り値（`stats_timeline_chart` の `price_bottom` と、出来高の棒の `count`。A05-9）。`SiteStatistics` の 2 つの `total`（母音スペクトル・特徴ランキング）はテストが参照しているので消さず、D1-12 で注記する（P-02 の PR-3） | 存在しない機能（Article など）を推測させない | 上記のファイル | 低 | —（参照が無いことを検索で確認済み。A02-6・A05-9 は削除の直前に再検索する） | C-16、M-15、T-15、A02-6、A05-9、PR-3 |
| R2-02 | 使われていないビューと i18n を消す。<br>・`shared/icons/_crown`・`_sparkle`<br>・ja.yml の `admin.annotations.nav` / `today`<br>・en.yml の `hello`<br>・ja.yml の `admin.word_candidates.title`（A04-13） | 使える部品に見える残骸を無くす | app/views/shared/icons、config/locales | 低 | —（参照が無いことを確認済み） | C-16、CFG-12、DOC-16、A04-13 |
| R2-03 | 使われていない JS を消す。<br>・inline_add の `escapeHtml` の export を外す（同じファイルの中でしか使っていない）<br>・`_feature_fields` の `.js-feature` クラス | 他から使われていると誤読させない | inline_add_controller.js、admin/annotations/_feature_fields.html.erb | 低 | — | J-19 |
| R2-04 | 使われていない CSS セレクタと、効いていない宣言を消す。<br>・確認済みの8セレクタ: `.btn--danger`・`.field--keyword`・`.icon--lg`・`.reading-column`・`.search-switch`・`.tag--static`・`.word-sense-fields`・`.word-sense-feature-fields`<br>・`.is-admin .proposal`、`.admin-status-tabs .is-current`、`.page-eyebrow .icon`、`.stats-grid__item dt .icon`（**要確認**）<br>・孤立したコメント<br>・効いていない宣言: admin.css の box-shadow:none の規則、`.ann-sense.is-complete` の border-color、打ち消す相手の無い `border-bottom:0`、同じ規則の中で打ち消される `margin-left:auto`、基本と同じ値の繰り返し、直後に上書きされる `border:none`、通常時と同じ色の hover<br>・`.stats-grid` の効いていない margin、components.css の管理表の色（admin.css が常に上書きしている）<br>・未使用のトークン `--shadow-soft`<br>・`.word-cloud__text` の効いていない `paint-order: stroke` と、そのコメント（stroke がどこにも無い。A02-5） | 削除済みの部品が使える部品に見える状態を無くす | admin.css、annotate.css、candidates.css、components.css、layout.css、tokens.css、docs/design.md（`--shadow-soft` への言及） | 低 | 削除の前後で、代表ページの computed style を一時スクリプトで比べる。比べる状態に、:hover と :focus-visible の強制、ダーク、767px と 560px の幅、管理画面を含める（P-02 の PR-15）。T0-09 を先に入れる（§6 の第3群） | S-03、S-04、S-05、S-07、A02-5、PR-15 |
| R2-05 | 設定とタスクの残骸を片付ける。<br>・`config/deploy/staging.rb`（全行がコメント）<br>・Capfile の、存在しないディレクトリへの glob<br>・Rails の雛形の英語コメント（routes.rb の末尾、db/seeds.rb の冒頭、deploy.rb の例示）<br>・stats.rake がトップレベルで `def` しているのをラムダにする<br>・`app/views/robots/show.text.erb` の `#` の行は、/robots.txt にそのまま出る本文なので、雛形の英語コメントに見えても対象外（P-02 の PR-8）。<br>・完了条件: `bundle exec cap -T`（SSH に接続しない）が通ること（PR-14）。 | 使っていない設定を、使っているように見せない | config/deploy/staging.rb、Capfile、config/routes.rb、db/seeds.rb、config/deploy.rb、lib/tasks/stats.rake | 低（デプロイの設定だが、本番のデプロイ経路は変わらない） | — | CFG-14、CFG-17、PR-8、PR-14 |
| R2-06 | テストの残骸を片付ける（期待値は変えない）。<br>・stats_vowel_graph_test の効果の無い `Rails.cache.delete`（test 環境は null_store）<br>・`create!` に渡している派生値の引数（保存時に上書きされるうえ、値も誤っている） | 「create! にも派生値を渡すもの」という誤解を防ぐ | test/system/stats_vowel_graph_test.rb、test/models/word_request_duplicate_check_test.rb、test/helpers/words_helper_test.rb | 低 | — | T-07、T-11 |
| R2-07 | **CSS の無い残骸クラスをビューから消す**（HTML の class 属性からトークンが減るだけで、見た目と意味構造は変わらない）。<br>・`sense-attrs__item--wide`（words/show の 3 か所。CSS は 1f51389 で消えた。A07-1）<br>・同名の CSS がどこにも無い単独のクラス 8 件（`stats-header`・`cand-decisions` など。A07-2）<br>・§4.4 の規則に照らして用途の無い要素・修飾子（A07-3。A05-9 の CSS の無いクラスを含む）<br>・消す前に、JS・テスト・i18n・ヘルパから参照されていないことを 1 件ずつ検索で確かめる。目印として残すものは、ビューに 1 行コメントを置く<br>・補間で組み立てる修飾子の値（`entity-treemap__cell--normal` など）は、§4.4 で「CSS に列挙して残す」側なので対象外。D1-16 で列挙する（P-02 の PR-16）。 | スタイルの在処を探させる名前を無くす | app/views の該当ファイル（一覧は A-07 の報告） | 低 | 消す前後で、該当ページの HTML を class 属性を除いて比べる | A07-1、A07-2、A07-3、A05-9、PR-16 |

### 区分 C3: 正典への集約（振る舞いを変えない）

リスクの低いものを先に並べている。各項目の前に、その行の「先に必要な特性テスト」がそろっていることを確かめる。

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| C3-01 | **基準値・しきい値・マジックナンバーを、その概念の持ち主に寄せる**。<br>・BulkWordRegistration の別名定数（MIN_READING_LENGTH・SIMILARITY_THRESHOLD）をやめ、持ち主の定数を直接参照する。<br>・立項スコアの境界（`<= 3` / `>= 4`）・範囲（1..5）・確信度の値を AnnotationProposal の定数にする。<br>・JAPANESE_ORIGIN_NAME を SeedCatalog の定数から参照し、「カタログに含まれる」ことを確かめるテストを足す。<br>・site_statistics の文字種の記号を、CharTypePattern の定数から組み立てる。<br>・genres/index の横棒の長さを、RadialChart の百分率のメソッドから求める。ビューと同じ演算順（`20 + d * 80.0 / span` を丸める）で計算する。比率（0.575 など）を 100 倍してから丸めると、浮動小数点の誤差で 1% ずれる場合がある（P-02 の PR-7）。`RadialChart.points` は 3 項目未満で空を返すので、points からは取らない。完了条件: 旧式と新式を d・span の範囲で総当たりして一致を確かめるテスト。<br>・収録リクエストの重複チェックのレート上限を定数にし、テストもそれを参照する。<br>・ホームの RANKING_LIMIT（10）と、ビューの `take(5)` の食い違いを直す（**要確認**: 6件目以降を使う箇所が無いこと）。<br>・ja.yml の「10文字」は、ルールそのものを述べる管理画面の説明文だけを `%{min}` で補間する。公開側の紹介文には「MIN_READING_LENGTH と一致させる」と YAML に注記する。<br>・補完監査の分（値はどれも変えない）:<br>　- 母音の数 5 を `SiteStatistics::VOWELS.size` から導く（A01-6）。<br>　- 書き出し画面の件数の上限 200 を定数にする（A04-5）。<br>　- 母音遷移の正規表現の上限 15 を `SiteStatistics::TRANSITION_MAX_POSITIONS` から組む（A05-4）。<br>　- 形態素の「2 文字以上」を `MorphemeFrequencies::MIN_LENGTH` にして、stats.rake から参照する（A02-10）。<br>　- 立項スコアの範囲を `ENTRY_SCORE_RANGE` にする。Ruby 側だけで、SQL に範囲を足すのは §7.1（A08-8）。 | 基準を変えるときに直す場所が1つになる | app/models（bulk_word_registration・annotation_proposal・bulk_proposal_approval・word_candidate・word_candidate_notation_import・word_sense・word_sense_search・site_statistics・morpheme_frequencies）、app/controllers（home・word_requests）、app/helpers/stats_helper.rb、app/views（admin/words/duplicates・admin/annotation_proposals・genres/index・home/index）、lib/tasks/stats.rake、config/locales/ja.yml、該当テスト | 低〜中 | 既存の word_request_form_test・annotation_proposal_test・bulk_proposal_approval_test。T0-14（母音遷移の境界値）。変更の前後で該当ページの HTML を比べる。T0-21 | M-10、SPEC-18、SPEC-13、SPEC-20、CFG-07、C-17、M-17、T-04、A01-6、A02-10、A04-5、A05-4、A08-8、PR-7 |
| C3-02 | **提案 payload のキーの一覧を1か所にまとめる**。<br>・AnnotationProposal に SENSE_KEYS / META_KEYS / PAYLOAD_KEYS を置き、AnnotationProposalImport・`legacy_sense_hash`・ReannotationExport から参照する。<br>・トップレベルの `linguistic_features` を保持しないことを、コメントで表明する。<br>・補完監査で見つかった残りの 5 か所（`SenseProposal` の読み取りメソッド、`ReannotationExport#sense_entries`、`FeatureResearchExport`、schema.json、テストのフィクスチャ）も、この定数を参照するか、写しであることと正の場所を書く（A08-1）。<br>・`legacy_sense_hash` が読みに行くトップレベルの `reading` は、取り込みで先に捨てられて届かないので消す（振る舞いは変わらない。A08-1）。<br>・取り込みのコメント「想定外のデータを溜め込まない」を、「トップレベルだけ選別し、senses の中身は丸ごと保持する」に直す（A08-1）。 | キーを足すときに直す場所が1つになる | annotation_proposal.rb、annotation_proposal_import.rb、reannotation_export.rb、feature_research_export.rb、.claude/skills/word-annotation-research/schema.json、テストのフィクスチャ | 低 | T0-10 | M-05、A08-1 |
| C3-03 | **一括登録での調査 JSON の読み取りを、ResearchJson.array_at に寄せる**。<br>・Hash でない要素の扱いが揃うので、現状を特性テストで確かめてから置き換える。<br>・AnnotationProposalImport はフェンス付きの JSON を受け付けるようになり、受理範囲が変わるため対象外とする（§7.1）。その旨をコメントに書く。 | 取り込みの手本が1つになる | app/models/bulk_word_registration.rb、annotation_proposal_import.rb（コメントのみ） | 低 | T0-16 | M-12、DOC-10 |
| C3-04 | **外部コマンドの有無の判定を、クラスで1回に揃える**。<br>・ReadingExtractor（呼び出しのたびに `mecab --version` を起動している）と MorphemeExtractor を、ShareCardRenderer の形（クラスでメモし、`available?` を公開する）にする。<br>・テストの skip も、サービスの `available?` を見る形に揃える。<br>・MeCab の呼び出しにタイムアウトを足すのは、振る舞いが変わるので対象外とする（§7.1）。<br>・`ReadingExtractor#normalize` を公開メソッドにし、/expand のスキル（`reading_length.rb`）は `send` をやめてそれを呼ぶ。メソッドに「スキルからも呼ばれる」と書く（DOC-19。§4.8）。<br>・lib/tasks/stats.rake は `MorphemeExtractor` のインスタンスの `available?` を呼んでいるので、インスタンスメソッドも残す（P-02 の PR-11）。<br>・rescue の範囲（ReadingExtractor は StandardError、MorphemeExtractor は SystemCallError など）と、判定に終了コードを使うかどうかは変えない。判定をクラスでメモすると、MeCab を入れたり外したりした後に再起動が要るようになるので、overview の外部コマンドの表にそう書く（PR-11）。 | 外部コマンドの手本が1つになる | app/services/reading_extractor.rb、morpheme_extractor.rb、test/services の該当ファイル、.claude/skills/word-expansion-research/reading_length.rb、lib/tasks/stats.rake | 低 | T0-02。`reading_length.rb` を変更の前後で同じ入力に流し、出力が同じことを確かめる。MeCab のある環境で `bin/rails stats:morphemes SURFACES_FILE=…` を前後で流し、db/morpheme_frequencies.json の counts が同じこと（generated_at は除く） | M-14、T-16、DOC-19、PR-11 |
| C3-05 | **認証の開放を明示し、小さな曖昧さを取り除く**。<br>・WordRequestsController の `allow_unauthenticated_access` に `only:` を付け、全アクションを列挙する（ルートを確認し、挙動は同じ）。<br>・words_helper で、リクエストの `params` を隠している局所変数の名前を変える。 | 公開側の開放範囲がコードから読める | app/controllers/word_requests_controller.rb、app/helpers/words_helper.rb | 低 | 既存のテスト | C-15、C-22 |
| C3-06 | **管理画面の判定を `admin_page?` の1つにする**。いまは、パスの前方一致とコントローラの型の2通りで判定している。layout の body のクラス・ヘッダーの現在地・共通ナビを、すべてこれに揃える | admin.css が効くかどうかと、管理ナビの表示が、同じ規則で決まるようになる | app/views/layouts/application.html.erb、shared/_header.html.erb、app/helpers/admin_helper.rb | 低 | T0-07 | S-09、C-18 |
| C3-07 | **管理画面で重複している UI を1つにする**。<br>・アノテーション・キューの絞り込み UI（コンソールとデッキに複製されている）を、パーシャルと、Admin::AnnotationQueue の定数・ヘルパにする。<br>・登録予定単語の状態ラベルを、ヘルパ経由に統一する。<br>・管理一覧の状態タブを STATUS_FILTERS から組み立てる。<br>・補完監査 A-04 の分（HTML は同一に保つ。新しいパーシャルは strict locals で宣言する。§4.2）:<br>　- 提案パネルの見出しのバッジ・注記・語義のループ（1 語コンソールとデッキに複製）を、`_proposal_meta`・`_proposal_notes`・`_proposal_senses` にする（A04-3）。<br>　- JSON のコピー欄（4 か所）を 1 つのパーシャルにし、「コピー」「コピーしました」の文言を 1 組にする（A04-4。JS が textarea から読む形にするのは §7.7）。<br>　- 2 つの書き出し画面の範囲・件数の欄を 1 つのパーシャルにする（A04-5）。<br>　- 特徴の用語解説パネル（デッキと語義欄に複製）を 1 つのパーシャルにする（A04-9）。<br>　- 「すべての語」の下端のバーを、共通の `_bar` か、共通部分だけの `_selection_controls` に寄せる（A04-10）。<br>・書き出しの textarea の name（`#{step}_export`）は 3 本の controller テストが固定しているので、パーシャルにしても保つ（P-02 の PR-16）。 | 同じ UI を片方だけ直す事故を防ぐ | app/views/admin/annotations・annotation_decks・annotation_proposals・candidates、app/controllers/admin/candidates、admin/words/index、app/helpers/word_candidates_helper.rb、config/locales/ja.yml | 低 | 既存の管理画面のテスト。描画した HTML を前後で比べる | C-13、C-14、A04-3、A04-4、A04-5、A04-9、A04-10、PR-16 |
| C3-08 | **ページネーションの計算を値オブジェクトにする**。3つのコントローラにある同じ計算を Pagination にまとめる。マークアップの統合は §7.7 | 計算の手本が1つになる | words_controller.rb、admin/words_controller.rb、admin/word_requests_controller.rb | 低 | T0-17 | C-09 |
| C3-09 | **50音表の定義をモデルへ移す**。SearchesHelper::KANA_COLUMNS を、行の定義を持つ KanaRow へ移す。ヒートマップの描画の統合は §7.7 | 表の定義の持ち主が一意になる | app/helpers/searches_helper.rb、app/models/kana_row.rb、3つのビュー | 低 | 既存の browse・stats・search のテスト | C-10 |
| C3-10 | **キャッシュの書き方を正典に寄せる**。<br>・sitemap・llms-full の「1日」を PublishedWordsDigest の TTL 定数にする（2つはすでに同じ値）。<br>・ホームの集計キャッシュの、リテラルで書いたキーを定数にする。<br>・「今月の新収録」の式（home_controller と site_statistics にある同じ式）を1か所にする。<br>・TTL の値は変えない。<br>・ホームと About（`PagesController#about` の収録語数）のコントローラにある `Rails.cache` を、集計クラスへ移す。キーには版を付け、TTL は変えない（§4.2。P-02 の PR-12）。 | 同じ種類のキャッシュを足すときの手本が1つになる | app/controllers（home・sitemaps・llms）、concerns/published_words_digest.rb、app/models/site_statistics.rb、app/controllers/pages_controller.rb | 低〜中（キーが変わるので、切り替えた直後に1回だけ作り直しが走る） | 既存の published_words_digest_test など | C-04、C-08、M-17、M-18、PR-12 |
| C3-11 | **テストの書き方を正典に寄せる**（期待値は変えない）。<br>・test_helper に with_rails_cache / with_fragment_cache / with_config（元の値に戻す）/ with_env / CANONICAL_HOST 定数 / create_published_word を置き、各ファイルの局所的な定義をこれに置き換える。<br>・管理画面のログインを `setup { sign_in_as(admins(:one)) }` に揃え（`Admin.take` をやめる）。`Admin.take` はいま admins(:two) を返している（フィクスチャの id が one より小さいため）ので、置き換えた後に admins(:two) の参照が無くなったことを確かめてから消す（P-02 の PR-16）。<br>・フィクスチャの呼び出しを覆い隠している局所変数 `words` の名前を変える。<br>・422 の記号を `:unprocessable_content` に揃える（アプリ側の10か所も揃える。値はどちらも 422）。 | テストの手本が1つになる | test/test_helper.rb、`Admin.take` を使うテスト 14 ファイル（sessions_controller_test.rb と session_test.rb を含む）、該当するテストとコントローラ | 低 | —（既存のテストが守る） | T-11、T-14、T-15、T-17、T-18、C-22、PR-16 |
| C3-12 | **読み由来の派生値の組み立てを1か所にする**。<br>・`WordSense.reading_derivations(reading)`（5つの値を Hash で返す）を作り、before_validation・backfill:reading_metrics・backfill:verify の3か所がそれを使う。<br>・reading_metrics と verify に ring_crossing_count を加える。<br>・verify では、words の代表値も WordSenseMetrics の集計と突き合わせる。<br>・reading_metrics の最後に `WordSenseMetrics.refresh!` を呼ぶ（update_columns はコールバックを通らないため）。<br>・D1-04 と組にして行う。<br>・`WordSenseMetrics.refresh!` は words.updated_at を進めないので、sitemap・ETag の版は動かない（P-02 で確認）。 | 派生値の出どころが1つになり、新しい派生列の足し忘れが起きにくくなる（ring_crossing_count で1回起きている） | app/models/word_sense.rb、lib/tasks/backfill.rake、test/tasks/backfill_task_test.rb、docs/data-model.md、CLAUDE.md | 中（運用タスクの欠陥の修正で、rake が書く値と出力が変わる。§0.2 の例外。P-02 の PR-10） | T0-11。ring_crossing_count を壊して検出・修復されることを確かめるテストは、本体と同時に足す | M-01、CFG-02、T-06、DOC-05、PR-10 |
| C3-13 | **ビューで派生値を計算し直すのをやめる**。_kana_ring は保存列の ring_crossing_count を使う。保存列は NULL を許すので、else は消さずに「NULL のとき」の表示として残す（P-02 の PR-2）<br>・統計のビューでの小さな再計算（`_vowel_graph` の割合、`_entity_cell` の塗りの濃さ、§8 の強調部分の切り出し）を、ヘルパか `SiteStatistics` が返す値にする（A01-7）。 | 表示と保存列の出どころが1つになる | app/views/words/_kana_ring.html.erb、words/show.html.erb、app/views/stats の該当パーシャル、app/helpers/stats_helper.rb | 中（公開の詳細ページの値の出どころが変わる） | C3-12 の後、かつ**本番で C3-12 版の `bin/rails backfill:verify` を流し、ring_crossing_count の不整合が 0 件であることをオーナーに確かめてもらった後**（§6 で第5群を C3-12 の後で区切る。PR-2）。詳細ページの円環の既存テスト。統計の既存テストと、描画した HTML の前後比較 | M-17、M-15、A01-7、PR-2 |
| C3-14 | **代表語義と語義の順序を1か所で定める**。<br>・`Word#primary_sense`（最小の id）と `Word#ordered_senses` を作る。<br>・これを使う箇所: related_words・shiritori_words・word_share_card・proposal_application・bulk_annotation と、ホーム・一覧・詳細のビュー。<br>・ホームの「読みが長い」の数値（先頭の語義の値か、max_reading_length か）は値が変わりうるので対象外とする（§7.1）。<br>・words/index は、代表語義ではなく「表示中の語義のうち読みが最長のもの」を選んでいる（`max_by`）ので、primary_sense に置き換えない（P-02 の PR-16）。 | 「代表の語義」の定義が1つになる | app/models（word・related_words・shiritori_words・word_share_card・proposal_application・bulk_annotation）、app/views（home/index・words/_entry_row・words/show・words/index） | 中 | T0-05。T0-15（og:image の版） | M-11、C-02、PR-6、PR-16 |
| C3-15 | **かなの畳み込みを KanaFold にまとめる**。<br>・RhythmPattern と MoraCount にある同じコピー（カタカナ→ひらがな）を共有にする。<br>・NFKC を掛けるひらがな→カタカナの3実装（word_request_duplicate_check・kana_row・site_statistics）を `KanaFold.to_katakana` にする。<br>・WordCandidateDuplicateCheck が WordRequestDuplicateCheck.fold に依存しているのを、KanaFold への依存にする。<br>・NFKC を掛けない2実装（search_regexp・words_helper）と ReadingExtractor（ゕゖ を落とす範囲）は、今の変換を名前付きで保つか、KanaFold との違いをコメントに書く。<br>・`ReadingExtractor#normalize`（C3-04 で公開する。/expand のスキルが呼ぶ）の名前と戻り値は変えない（DOC-19）。 | 8通りある書き方の手本が1つになる | app/models の該当ファイル（新規 kana_fold.rb）、app/helpers/words_helper.rb、app/services/reading_extractor.rb | 中（RhythmPattern / MoraCount は保存済みの派生値に関わる） | T0-18。T0-15（og:image の版。共有カードの円環の点が KanaRow を通る） | M-04、PR-6 |
| C3-16 | **絶対 URL の組み立てを SiteUrl にまとめる**。<br>・canonical_host を直接読んでいる10か所以上と、3つの流儀（手で組み立てる・absolute_site_url・パスの直書き）を SiteUrl（host / absolute(path) / 既定の og 画像パス）に寄せる。<br>・共有カードを焼けるかどうかの判定（ヘルパとコントローラの2か所）も、WordShareCard の1メソッドにする。<br>・`SiteUrl` は「スキーム付きの起点」（`config.x.canonical_host` は `https://…`）と「裸のホスト」（共有カードの標識だけが使う）を、別々のメソッドで持つ（P-02 の PR-6）。 | URL の手本が1つになる | app/controllers（llms・robots・sitemaps・share_cards）、app/helpers/application_helper.rb・structured_data_helper.rb・words_helper.rb、jbuilder・builder・llms のテンプレート、pages/about、app/models/word_share_card.rb | 中（公開の出力に触れる。文字列は同一） | T0-01・T0-04 と、既存の meta_tags・structured_data・sitemaps・llms・robots・share_cards のテスト。T0-15（og:image の版） | C-05、PR-6 |
| C3-17 | **1語の直列化で使う共通部品を1か所にまとめる**。<br>・ジャンルのパスの区切り（i18n の genre_separator と、直書きの " › "）。<br>・ライセンスの名前と URL（structured_data_helper・_license.json.jbuilder・about・ja.yml）。<br>・出力の文字列は変えない（llms-full の凡例の誤りは §7.1）。 | 同じ語彙が画面ごとにずれる事態を防ぐ | app/helpers、app/views（jbuilder・llms・about・admin の該当ビュー）、config/locales/ja.yml | 中 | T0-01。既存の structured_data_test・llms_controller_test | C-06 |
| C3-18 | **コントローラにある業務規則をモデルへ移す**。<br>・今日の一語を `Word.featured_on(date, count:)` にする。count にはホームのキャッシュした語数を渡す（その場で数え直すと、公開・保留の直後に別の語が出る。キャッシュで省いていた COUNT も毎回に戻る。P-02 の PR-1）。<br>・新着順を WordSort の `"created_desc"`（同じ並び）に揃える。<br>・Atom 用の依存レコードを `Word#feed_cache_dependencies` として cache_dependencies の隣に置く。<br>・annotations_controller で4回ある提案の取得を before_action にする。<br>・管理一覧で、ジャンルを配下まで広げる処理を WordSense のスコープ1つにする（**要確認**: 公開検索と意味が一致するかを先に確かめる）。 | 規則を1か所で定めることになり、2つの画面が別々の結果を出す事態を防ぐ | app/controllers（home・words・admin/annotations・admin/words）、app/models/word.rb・word_sense.rb | 中 | T0-04（今日の一語はキャッシュの語数で選ぶことを含む）。T0-19 | C-11、PR-1 |
| C3-19 | **JavaScript の重複を共有モジュールにまとめる**。<br>・「表示中の語義」「全部完了しているか」の判定（publish_guard と deck で同じ処理）を、`controllers/support/` の関数にする。<br>・genre_filter の count を target として宣言する。<br>・vowel_graph の文言を、ja.yml の `searches.vowel_transition_value`（`%{}` 記法）の1本にする。<br>・`data-vowel-graph-label-value` の値が `{from}〜{to}拍目: {rows}` から `%{from}…` の記法に変わるので、/stats の HTML の data 属性の値が変わる（JS が描く文字は同じ。C3-20 と同じ扱い。P-02 の PR-16）。 | 判定と文言の手本が1つになる | publish_guard・deck・genre_filter・vowel_graph の各コントローラ、_genre_filter・_vowel_graph、ja.yml | 中（/stats の HTML の data 属性の値が変わる。表示は同じ） | 既存の console・deck・stats_vowel_graph のシステムテスト。T0-20 | J-05、J-13、J-14、PR-16 |
| C3-20 | **検索スライダーの値と文言をヘルパから渡す**。10 / 30 と「N文字以上」などの文言を、reading_counter_data と同じ形の data 値にする。JS 側のフォールバックの定数は消す<br>・feature_range の「（単語 未選択）」「（読み 未選択）」の直書きも、data 値で渡す（J-07。P-02 の PR-12）。 | 収録基準を変えたときにスライダーだけ取り残される事態を防ぐ | range_slider_controller.js、searches/index.html.erb、app/helpers/searches_helper.rb、ja.yml、feature_range_controller.js、admin/annotations/_feature_fields.html.erb | 中（/search の HTML に data 属性が増える。意味構造は変わらない） | T0-08 | J-07、C-17、PR-12 |
| C3-21 | **CSS の二重定義を1つにする**（見た目は変えない）。<br>・`.section-heading` の2つの定義を、実際に効いている値で1つにする。<br>・`.stats-grid` の 767px の gap を `.stats-grid--rows` のそばへ移す。<br>・`.is-admin` のトークンの2ブロックを1つにする。<br>・ヘッダー・フッター・管理ナビの 4 か所に直書きされたフレーム幅 1040px を `--frame-width` にする（値は同じ。A10-8）。 | どの値が効くかを1か所を読めば判断できる | components.css、admin.css、layout.css、tokens.css | 中（カスケードの順序に依存する） | T0-09。代表ページの computed style を前後で比べる（一時スクリプト）。比べる状態に、:hover と :focus-visible の強制、ダーク、767px と 560px の幅、管理画面を含める（P-02 の PR-15） | S-03、S-07、A10-8、PR-15 |
| C3-22 | **テストで公開語を作る方法を create_published_word に揃える**。いま `annotated_at` だけを立てて作っている24か所を、1ファイルずつ移す（語の状態が done に変わるので、キューに関わるテストに混ざらないかを1件ずつ確かめる） | 本番では起きない状態（公開済みなのに未対応）をテストで作らなくなる | test の該当ファイル | 中 | C3-11 | T-08 |
| C3-23 | **システムテストの操作ヘルパを ApplicationSystemTestCase に集める**。type_japanese・press・click_row の系統・with_window_size を移し、環境の制約の説明も1か所にまとめる（**要確認**: 実行して、どの入力手段が今の Chrome で通るかを確かめてから行う） | system テストの書き方の手本が1つになる | test/application_system_test_case.rb、system テスト4ファイル | 中（system テストは不安定になりやすい） | 変更後に test:system を3回続けて通す | T-09 |
| C3-24 | **登録予定単語の「段」の定義を 1 か所にする**。<br>・段と状態の対応・段の名前・書き出しのキー・画面のルート名が散らばっている。A04-7 が挙げた箇所に加え、P-02 で `WordCandidateReview::CHOICES` と `context:`、`apply_decisions(statuses:)`、確定した後の行き先 `next_stage_path`、`WordCandidate.in_progress` が見つかった。これを `WordCandidate` の定数表 1 つにまとめ、ヘルパ・コントローラ・`WordCandidateExport` はそこを引く。含めない定義があれば、含めない理由を書く。ビューの `current:` は、コントローラが渡す（A04-7・PR-9）。<br>・定数表は、段ごとの書き出しのキーを列として持つ。登録待ちの段の書き出しのキー "reading" は変えない（HTML の name `reading_export` と既存テストに出るため。PR-9）。<br>・登録待ちから一括登録へ渡す本文をビューで組み立て直しているのを、`WordCandidateExport#text`（`with_ids: false`）を呼ぶ形にする（出力が同一であることは P-02 で確認済み。A04-11）。<br>・確認の一覧の件数（印ごとの合算・既定の処理ごとの件数）を、値オブジェクトが数えて渡す（A04-12）。 | 段を足したり名前を変えたりするときに、直す場所が 1 つになる | app/models（word_candidate・word_candidate_export・word_candidate_review）、app/helpers/word_candidates_helper.rb、app/controllers/admin/candidates/*、app/views/admin/candidates/* | 中 | 既存の candidates のテスト。各段の画面の HTML を前後で比べる | A04-7、A04-11、A04-12、PR-9 |

### 区分 G4: AI 向けの案内の整備

| ID | 内容 | 効果 | 影響ファイル | リスク | 先に必要な特性テスト | 出典 |
|---|---|---|---|---|---|---|
| G4-01 | **CLAUDE.md を 200 行程度に再編する**。<br>・中身を「厳守事項」「正典パターン（手本ファイル付き。§4 の定義）」「どこに何があるかの地図（ディレクトリ → 役割 → 手本）」「合格判定コマンド」の4つに絞り、詳細は docs へリンクする。<br>・デザインの節（約78行）は design.md へ移し、禁止事項だけを残す。<br>・監査 DOC の再編案（[audits/docs-guides.md](audits/docs-guides.md) §2）に従う。<br>・デザインの節を design.md へ移すときも、design.md の既存の節番号は変えない（§4.7）。完了条件: `design.md §` の参照先がすべて実在すること（P-02 の PR-5）。 | 最初に読む文書だけで、正しい手本と禁止事項に辿り着ける | CLAUDE.md、docs/design.md、docs/overview.md | 中（AI の振る舞いに直結する） | — | DOC-07、DOC-12、M-03、C-15、C-21、CFG-12、PR-5 |
| G4-02 | **docs/history/ を作り、歴史と記録を隔離する**。<br>・移すもの: changelog.md、performance-report.md、launch-checklist の解禁の記録、design.md の改訂履歴と試作・計測の記録、stats.md の経緯と実装フェーズ、growth-strategy の現状評価、issues.md のうち失効した確定事項。<br>・各文書の冒頭に「現行の仕様ではない」と書く。<br>・「再提案しない」ための規約は、design.md の禁止事項の節にまとめて現行のまま残す。<br>・リンクを張り替える。<br>・節を移すときは欠番にして、行き先を 1 行残す（§4.7）。完了条件: `design.md §`・`stats.md §` の参照先がすべて実在すること（P-02 の PR-5）。 | 現行の仕様と経緯を取り違えなくなる | docs/ 配下と、それを参照する README.md・test/integration/published_words_digest_test.rb | 低 | — | DOC-12、SPEC-01、SPEC-11、SPEC-22、PR-5、PR-16 |
| G4-03 | **docs が現行のコードと一致しているかを最終確認する**。<br>・overview の画面一覧を確かめる。<br>・環境変数の表に「Rails / Puma の標準」「テスト用」「Actions のシークレット」の欄を足す。<br>・外部コマンドの表に「本番での有無」を足す。<br>・運用の章（デプロイ・CI・cron・claude.ai 用のスキル束の再生成）を新設する。<br>・JS の地図（コントローラの一覧・独自イベント・DOM の約束事）、CSS の実際の配置、DB 制約とモデルの検証の対応表、単一の出典の表を置く。<br>・件数は書かず、出どころを指す。<br>・README の「コードベースの規模」（日付付きの数値）は、消すか、数え方（コマンド）を添えて日付付きで残すかを決めて揃える（DOC-18）。<br>・JS の地図に、フック用の名前の付け方（§4.3）を書く（A07-5）。 | 探索の手数を減らす | docs/overview.md、docs/data-model.md、docs/design.md、README.md | 低 | — | DOC-07、DOC-08、DOC-13、CFG-08、CFG-09、CFG-11、CFG-13、J-02、J-15、S-02、SPEC-12、DOC-18、A07-5 |
| G4-04 | **コメントを「なぜ」だけにする**。<br>・直後のコードを言い換えただけのコメントを消す。見積もり: モデル 60〜80、JS 約30、コントローラ・ビュー・テストはそれぞれ2〜3割。<br>・残すのは、なぜ・不変条件・外部との約束・長いファイルの区画見出し。<br>・経緯（日付・Issue 番号・計測値）は、docs/history か changelog へ移す。<br>・領域ごとにコミットする。<br>・対象外: 出力されるコメント（`app/views/robots/show.text.erb` の `#` の行は /robots.txt の本文）と、共有カードの `share_cards/word.svg.erb`（SVG のバイト列が og:image の URL を決める）（P-02 の PR-8・PR-6）。 | 古くなって嘘になるコメントの発生源を減らす | app/、lib/、config/、test/ | 低（分量が多い） | — | 各報告の「コメントの傾向」、PR-6、PR-8 |
| G4-05 | この計画書と監査の記録を docs/history/ へ移す（完了時） | 作業文書を現行の仕様から分ける | docs/refactoring/ | 低 | — | — |

## 6. 実行順序

「文書・コメントの矛盾解消」と「リスクの低いもの」を先に行う。

0. **始める前**: 合格判定（§0.3）を一度通して、ベースラインを取り直す（§1）。結果は台帳の作業ログに書く。
1. **第1群（AI の操作を誤らせる嘘を先に消す）**: D1-01 → D1-02 → D1-03 → D1-05
2. **第2群（残りの文書・コメント）**: D1-06 → D1-19 → D1-20、D1-07 〜 D1-18、D1-21（D1-04 は除く。C3-12 と組にして行う）
   - D1-06・D1-19・D1-20 は同じスキルのファイルに触れるので、この順に行う。
   - D1-18・D1-21 の一部は、§7.5 の回答（A09-1・A10-1）で書き方が決まる。
3. **第3群（特性テスト）**: T0-01 〜 T0-21
   - 初版では残骸の削除の後だったが、前に出した。R2-04 が tokens.css を触る前に、T0-09（ダークの 2 ブロックの一致）を入れるため（P-02 の PR-15）。
4. **第4群（残骸の削除）**: R2-01 〜 R2-07（R2-07 は、D1-21 でクラス名の付け方を design.md に書いた後に行う）
5. **第5群（正典への集約）**: C3-01 〜 C3-24（表の順。C3-12 は D1-04 と組にする。C3-04 は C3-15 より先に行う）
   - **C3-12 の後で一度区切る**。ここで merge し（オーナーの指示による）、本番で C3-12 版の `bin/rails backfill:verify` を流して、ring_crossing_count の不整合が 0 件であることをオーナーに確かめてもらう。確かめてから C3-13 以降に進む（P-02 の PR-2）。
6. **第6群（AI 向けの案内）**: G4-01 → G4-02 → G4-03 → G4-04 → G4-05
7. **第7群（振る舞いの変更。オーナーが §7.1 から選んだものだけ）**: 改修の後に、改修とは別に 1 件 1 PR で直す。中身は §10 の質問 4 の回答で決まる。

台帳への写し方（P-03）:

- 1 項目を台帳 §5 の 1 行にする。1 行が 5 時間枠の 1/3 を超えそうな項目（D1-12・D1-14・D1-19・C3-07 など）は、ファイルのまとまりごとに `D1-12a` / `D1-12b` のように分ける。
- 推奨 effort は、派生値・キャッシュ・公開の出力・代表語義に触れる C3-10・C3-12・C3-13・C3-14・C3-15・C3-16・C3-17・C3-18 を max、それ以外を high にする（STRATEGY §3）。

作業の決まり:

- **1項目 = 1コミット以上**にする。特性テストは本体とは別のコミットにして、先に入れる。コミットメッセージは日本語で書き、接頭辞は `docs:` / `test:` / `refactor:` / `chore:` を使う。
- 各コミットの前に、§0.3 を全部通す（`docs/refactoring/` だけを変えるコミットは除く）。
- 「要確認」の付いた項目は、実測・実行で確かめてから着手する。結果は台帳の備考に書く。計画の前提が崩れたら、台帳 §6「受付箱」に書いて止まる。
- **計画外の問題を見つけたら、その場では直さず台帳 §6「受付箱」に書く**。
- **実行では、サブエージェントを使わず、リーダーが直列で行う**（P-02 の PR-4）。
  - 並列にしても総消費量は減らない（STRATEGY §1）。
  - 第2群の項目は、同じファイル（CLAUDE.md・data-model.md・design.md・stats_helper.rb・ja.yml など）を複数が触るので、並べると衝突するか、片方の修正が黙って消える。
  - G4-04 のように分量の多い項目は、台帳でディレクトリごとの行に分けて、直列に進める。
- **項目の種類ごとの完了条件**（§0.3 に加えて満たす）
  - i18n のキーを消す・移す項目（R2-02・C3-07・C3-17・C3-19・C3-20）: 消したキーを app・config・test で検索して 0 件であること。
    ローカルで `config.i18n.raise_on_missing_translations` を一時的に true にして（コミットしない）、テストが通ること（P-02 の PR-13）。
  - デプロイの設定（Capfile・config/deploy.rb・config/deploy/*・.github/workflows/deploy.yml・config/database.yml）に触れる項目（D1-01・R2-05）: `bundle exec cap -T`（SSH に接続しない）が通り、YAML が読めること（PR-14）。
  - 文書の節を足す・移す項目（D1-09・D1-10・D1-21・G4-01・G4-02）: `design.md §`・`stats.md §` の参照先が、すべて実在すること（PR-5）。
  - 共有カードの SVG の入力（代表語義・円環の点・標識のドメイン・テンプレート）に触れる項目（C3-09・C3-14・C3-15・C3-16）: T0-15 が通り、開発用 DB の全公開語の `WordShareCard#digest` が前後で同じであること（PR-6）。
  - computed style を前後で比べる項目（R2-04・C3-21）: :hover・:focus-visible の強制、ダーク、767px・560px の幅、管理画面の状態も比べる（PR-15）。
- push・PR・merge は、オーナーの指示があるときだけ行う（§0.2）。merge の区切りは群の切れ目にする（STRATEGY §5）。

## 7. 実施しないこと（理由つき）

### 7.1 外部から見える振る舞いが変わるもの（範囲外で見つかった不具合を含む）

直すと出力や挙動が変わるので、この改修では直さない。このうちコメントで表明できるものは、区分 D1 で表明する。**別の PR で直すことを推奨する**（特に C-01・C-03・J-03・J-17）。

| ID | 内容 | 変わるもの |
|---|---|---|
| C-01 | `/words` から「条件を変える」で `/search` へ移ると、条件が許可されずに落ちる（不具合）。落ちるのは、スカラ形の first_char・last_char・part_of_speech_id・entity_type_id・linguistic_feature_id と、reading_length・mora_count・vowel_transition | /search のフォームの初期状態 |
| C-02 | ホームの「読みが長い」の数値は先頭の語義の読みの長さを使っており、並び順（max_reading_length）とずれることがある | ホームの表示値 |
| C-03 | 詳細ページと Atom を public で HTTP キャッシュしているが、同じ HTML に、ログイン中だけ出る差分（ヘッダーの管理リンクとログアウトのフォーム）がある。ETag に認証状態を入れるか、ログイン中は private にする | Cache-Control / ETag |
| C-06 | llms-full.txt の凡例が「A=英字」になっている（小文字の a は別の文字種） | 公開テキスト |
| C-07 | Atom の `<published>` が created_at、`<id>` が request.host になっている | フィードの中身 |
| C-18 | フッターの管理リンク（admin_words_path）と、ヘッダーのリンク（admin_root_path）が違う | リンク先 |
| J-03 | 語義を複製すると、削除して非表示にした特徴の行が、見えないまま新しい語義に付いて保存される（管理画面の不具合。**要再現**） | 保存される内容 |
| J-17 | コピーボタンを2秒以内に2回押すと、「コピーしました」のまま元に戻らない（公開の詳細ページ） | ボタンの表示 |
| J-09 | nav_drawer は Turbo のキャッシュの前に閉じないので、「戻る」でドロワーが開いたまま復元されうる（推測） | 「戻る」の表示 |
| J-10 | queue_nav は、ボタンの上で押した Enter も保存に使う。入力中かどうかの判定が5通りあり、統一すると挙動が変わる | 管理画面のショートカット |
| J-04 | genre_picker は、子ジャンルの取得に失敗しても黙って捨てる | 失敗時の表示 |
| M-09 | 別表記や特徴の該当部分だけを変えたとき、詳細ページの ETag が変わらない疑いがある（**要調査**） | ETag |
| M-12 | 管理画面での提案の取り込みが、` ```json ` のフェンス付きの JSON を受け付けない | 受理範囲 |
| M-14 | ReadingExtractor の MeCab 呼び出しにタイムアウトが無い（CLAUDE.md の規約に反する）。足すと、長い入力で読みが空欄になりうる | 一括登録の読み |
| M-16 | 読みの改行を、収録リクエストでは空白に置き換え、語義では取り除く（処理が2通りある） | 保存される読み |
| M-18 | WordRanking の Rails.cache に race_condition_ttl が無い | キャッシュの作り直し方 |
| SPEC-13 | 収録基準（読み10文字以上）をモデルで検証する | 保存の可否 |
| CFG-08 | INDEXING_ENABLED は値を見ず、設定されているかどうかだけで決まる（`false` でも解禁になる）。Boolean として解釈するように変えるには、本番の値の確認が要る | noindex |
| CFG-12 | ja.yml の errors.messages に `greater_than_or_equal_to` が無い（足すとエラーの文言が変わる）。test で raise_on_missing_translations を有効にする件も、既存のテストが落ちうるので別途扱う | エラーの文言 |
| CFG-13 | DB にしか無い制約（admins.username の一意など）に、モデルの検証を足す。長さの上限をモデルの定数に移す | 検証の結果 |
| J-08・S-08 | Plotly のパレットをトークンから作る | ダークでのグラフの色 |
| J-11 | theme-color を読むトークンを変える | ブラウザの UI の色 |
| J-15 | /stats の段階的強化の流儀を揃える | /stats の HTML |
| S-04 | `.entry-row__go`（表示されないアイコン）をビューから消す | 公開 HTML |
| — | `sessions/new` の `value: params[:username]` | 管理者認証の画面には触れない |
| A04-1 | 特徴の再調査の書き出しで、「日本語のみ」のチェックを外しても絞り込みが外れない（確認済みの不具合。`check_box_tag` に、外したときの "0" を送る hidden が無い） | 管理画面の書き出しの対象 |
| A09-1 | 公開の取り消し（保留・削除）が、sitemap・llms-full・ランキング・統計のキャッシュに最大 1 日残る。直すなら、取り消しの後に該当のキャッシュを消す（§7.5 で許容されなかった場合） | 公開出力の鮮度・ETag |
| A01-1・A08-3 | `target_start` の位置に `target` があることを検証する。提案の `target_start` を反映で使う | 保存の可否・特徴の位置 |
| A01-2 | 同じ特徴×同じ `target` を同時に 2 つ作ると、一意索引で例外になりうる（推測） | 保存の可否 |
| A01-3 | 統計 §7 の「拍位置」の画面の文言を、「何番目の母音」などに改める | 公開の文言 |
| A01-4 | 分布の最頻値の規則（「30+」をまとめたビンを最頻の対象にするか）を 1 つにする | 統計の印（端の場合） |
| A02-1・A02-10 | ワードクラウドで落ちた語や、壊れた集計ファイルをログに出す。最大の級数を枠幅に収める | ログ・語の配置 |
| A02-9 | 共有カードの書体の判定を、「Noto Sans CJK JP があるか」に狭める | og:image が出るかどうか |
| A04-6 | 登録予定単語の「元の語」「系統の子」の判定を 1 つにする | 管理画面の札とインデント |
| A04-8・A04-15 | 確信度を i18n のラベルで出す。語種の属性名・モデル名の訳を足す | 管理画面の表示文言 |
| A05-1 | 統計 §8 のリード文の「実例の下線」を、実装（淡い面のハイライト）に合わせる | 公開の文言 |
| C-20・A06-1〜A06-4・A06-7 | マスタ名の正規化（前後の空白の除去）と衝突の扱いをモデルに揃える。タグ統括管理の競合時の 500 を 422 にする。名前の長さの上限を検証する。名前の一致判定を ai_ci に揃える | 管理画面の新設・名前解決・エラー |
| A07-4 | 提案の confidence の値域を、取り込みで検証する | 取り込みの受理範囲 |
| A08-6・A08-7 | 不完全な特徴・別表記を除外したことを知らせる。一括承認のゲートで保存時の検証を先に行い、失敗した語を示す | 管理画面の表示・一括承認の対象 |
| A08-8 | `needs_review` の SQL にも立項スコアの範囲を足す | キューの絞り込み |
| A08-9 | 取り込みで `surface` と `version` を照合する | 取り込みの通知・受理範囲 |
| A10-4・A10-11 | 閉じたドロワーを inert にする。JS が無いときのナビを出す。ナビのランドマークに名前を付ける | キーボード操作・読み上げ |
| A11-12 | 画面に残る「言語的特徴」（ja.yml の 3 か所）を「言語学的特徴」にする | 画面の文言 |

### 7.2 スキーマ・インフラ・依存の変更

| ID | 内容 | 理由 |
|---|---|---|
| DOC-01・CFG-01 | deploy.yml を、CI が成功した後に走らせる（`workflow_run` など） | インフラの変更。GitHub のブランチ保護（main への merge に CI の通過が必須か）も未確認。別途相談する |
| CFG-14・C-16 | `require "rails/all"` を、使っているフレームワークだけに絞る（Action Cable・Active Storage・Action Mailbox のルートが生えている） | フレームワークの構成の変更。eager load の確認が要る |
| CFG-15 | config/puma.rb で、単一モードでの `preload_app!` の分岐を消す | 本番の起動設定 |
| J-11・C-22 | CSP を導入する（`nonce: true` は効いていない） | GA4・Plotly の読み込みに影響する |
| CFG-04 | `word_sense_features.target` / `target_reading` を as_ci にする | スキーマの変更 |
| M-20 | 公開状態を annotated_at と annotation_status の2列で持つ設計を見直す | スキーマの変更 |
| PR-2 | `word_senses.ring_crossing_count` に NOT NULL を足す（いまは NULL を許すので、C3-13 で else を残す） | スキーマの変更 |
| A11-2 | 読み（`word_senses.reading`）をカタカナに正規化する。または、特徴の照合で字種を同一視する（開発用 DB にひらがなの読みは 0 件） | 既存データの読みが変わる |

### 7.3 既存テストの削除・期待値の変更

「既存テストの期待値を変えない」という制約に当たるので、この改修では行わない。CLAUDE.md の方針（役目を終えたテストは残さない）には沿うものなので、承認があれば別の PR で整理する。

- T-02: 未ログインの拒否を個別に検証しているテスト3本（admin_authentication_test と重複している）を消す。
- T-13: 同じ式を検証している重複テスト、廃止した機能の不在確認（related_words、pages の `.page-toc`）、`assert_routing` の置き換え、`_exclude` を2つの層で検証している件。
- SPEC-24: pages_controller_test の `.image-slot` の不在確認。
- T-10: word_request_form_test のうち、サーバの描画で確かめられる部分を結合テストへ移す。
- T-17: 画面の文言を直書きしている assert を、I18n.t の参照にする。
- C-19: 一括登録の2画面でフラッシュが二重に出る（テストが現状を固定している）。
- tag_kind_test の意味の無い assert を消す。テスト用の参照実装・メソッド（`Levenshtein.far_apart?` / `distance` など、`WordRequestDuplicateCheck::Match#exact?`、`MorphemeCloud::Placed#top` など）を消す。いずれもテストの変更が伴うので、消さずに「テスト用」と注記する（D1-12）。
- A10-1: ΔRGB の式を最大差に揃える場合は、`design_tokens_test.rb` の `delta_rgb` を変える（§7.5 の回答による）。

### 7.4 見た目が変わる CSS の変更

- S-11: design.md の規則から外れている箇所。2px の罫、box-shadow のリング、reduced-motion の対象外になっている transition、円環の線幅 1.2、ヒーローの 26px、767px 以下で 16px にする入力欄の漏れ。どちらを正とするかはオーナーが判断する。
- S-06: 値が少しずつ違う部品の統一。フォーカスの輪、下線タブ、5系統ある表、キーの表示、白い地に白い面を重ねた「見えない囲い」。
- S-07: 管理画面では `--radius` が 3px なのに、`--radius-sm` が 6px のまま。
- S-02: 管理用の CSS を、公開ページでは読まないようにする（配信する CSS が変わる）。
- SPEC-20: color-mix の下地（transparent と `--bg`）を統一する。
- A02-4: 欧文の幅表の値（`Z`・記号）を実測に合わせる（ワードクラウドの配置が変わりうる）。
- A05-2・A05-3: 統計の塗り分けの明度を直す。地を `--surface` に寄せ、チントの式を 1 本にする。
- A05-10: 「最多」を `:first-child` ではなく `.is-top` のクラスで示す（HTML が変わる）。
- A10-2: 公開側のタップ領域を 44px に揃える（ボタン・タグ・ナビ・フッターの寸法が変わる）。
- A10-3: 管理一覧の行の hover で、状態の色が AA を割らないようにする。
- A10-6: ブレークポイントの数を減らす。
- A10-8: 560px 以下で、ヘッダーとフッターの左右の余白を揃える。

### 7.5 オーナー判断が要るもの

- **S-01 管理画面のダーク表示**: admin.css の上書きがライトの値で固定されており、ダークでは補足の文字がほぼ読めない（既知）。ダークに対応するか、管理画面をライトに固定するか。
- **SPEC-07・C-08 「ジャンル数」の定義**: 画面ごとに3通りある。ホームは小分類の総数、/genres は公開語義があるジャンルの数（ジャンル無しを含みうる）、/stats は使われている小分類の数。どれに揃えるか。この改修では、コメントの誤り（「同じ定義に揃える」）だけを直す。
- **DOC-11・SPEC-19 「言語学的特徴だけの再調査」の書き出し**: 受け取るスキルが無い（確定事項 32・37）。撤去するか、使わない旨を画面と research/README に書くか。
  使い続けるなら、A04-1（「日本語のみ」の絞り込みが外れない不具合）を直すかと、A08-10 の注意書き（単一語義の語だけ正しく反映される）を D1-20 で足すかも決まる。
- **CFG-06 開発用のダミーデータ**: 2系統ある。`db/seeds/development.rb` は公開状態の語を作り、`bin/rails dev:sample_data` は未公開の語とカタログに無いマスタを作る。どちらを正とするか。
- **CFG-14 Dockerfile 一式**: Dockerfile・bin/docker-entrypoint・.dockerignore は、どの文書にも言及が無い。残すか。
- **D1-09 の方針**: 実装（CSS）を正として design.md を直す。文書のほうを正としたい項目があれば、承認のときに指定してほしい。
- **A09-1 公開の取り消しの遅れ**: 公開を取り消した語（保留・削除）が、sitemap・llms-full・ランキング・統計のキャッシュに最大 1 日残る。
  sitemap と llms-full については、性能のための意図的な割り切りとして `published_words_digest.rb` のコメントに書かれている。
  許容するか。推奨は「許容して、D1-18 で data-model §8 に書く」。即時に消したい語が出る運用なら、§7.1 で直す（第7群）。
- **A10-1 ΔRGB の式**: CLAUDE.md の「面・罫は白との差 ΔRGB 19 以上」を、テストは各チャンネルの差の合計、design.md と layout.css のコメントは最大差で測っている。どちらに揃えるか。
  - 最大差に揃える: 文書どおりの厳しさを保てる。ヘッダーの面の色を決めたときの判断も、この式によっている。
    ただし、テストの式を変える（§7.3）。ダークの `--bg-tint` が不合格になるので、色を直すかの判断も要る（§7.4）。
  - 合計に揃える: 見た目もテストも変わらない。ただし基準がゆるくなる（合計 19 は、1 チャンネルあたり 6〜7 の差でも満たす）。文書とコメントの数値の書き直しも要る。
  - 推奨は最大差。CLAUDE.md の規則の意図に近い。
- **A11-5 /harvest の「発表直後の公式名称」**: /harvest は「慣用性を満たす」、ガイドラインは「新しすぎるものはグレー（スコア 3）」としている。どちらに揃えるか。
- **A11-9 熟字訓の定義**: glossary は訓読みに限るが、注釈スキルの例（上手 → ジョウズ）は広い定義を使っている。
  既定では glossary を正として、スキルの例を差し替える（D1-19）。定義を広げたい場合は glossary を直す。
- **A11-11 品詞「連語」と中分類「絵画様式」**: どのスキルも使い分けに触れていない。スキルにどう書くか。
- **A04-13 提案の状態 `dismissed`**: 立てる箇所が無く、表示・i18n・CSS が使われることがない。将来の見送り操作のために残すか、撤去するか（DB の値 2 の扱いを伴う）。

### 7.6 （廃止）

初版で「所有者の作業中のファイル」に回した項目は、ファイルがコミットされたので改修の対象に戻した（§0.2）。DOC-02 の README の分は D1-02、DOC-03 の word-expansion-research の分は D1-06、DOC-19 は C3-04 で扱う。

### 7.7 効果に比べて分量・リスクが大きいもの（今回は見送る）

- **CSS**
  - CSS をファイル間で移動する（S-02。カスケードの順序が変わる）。
  - 余白の px の直書き約320か所をトークンにする（S-07）。
  - `font-weight: 400` の49か所を整理する（要素ごとの確認が要る。S-05）。
  - 見た目が完全に同じ規則をまとめる（S-06。規則の位置が動く）。
- **ビューの統合**
  - 50音のヒートマップの描画をパーシャルにまとめる（C-10）。
  - ページネーションのマークアップをまとめる（C-09）。
- **JavaScript**
  - DOM の生成方式を統一する（J-16）。
  - 「その場追加」の二重実装をまとめる（J-04）。
  - サーバ側の規則を JS へ受け渡す（J-06）。
- **モデル**
  - 結果オブジェクトの形を統一する（M-19）。
  - トランザクションの張り方を統一する（M-13。今回は MySQL 依存の注記だけ）。
  - 重複チェックの3実装をまとめる（M-06。違いは意図なので注記だけ）。
- **書き方の全面統一**
  - Strong Parameters を全面的に統一する（C-15。生の `params[:x]` が約60か所ある）。
  - i18n の相対キーと絶対キーを全面的に統一する（CFG-12・C-21。新しいコードの規則だけを決める）。
  - llms テンプレートを i18n にする（C-21）。
  - 日付の書式を `l()` に統一する（C-22。表示が変わりうる）。
- **検索エンジンから見える挙動**: インデックスしてよいかの規則が、ビュー・ヘルパ・モデルの3層にある（C-17）。今回は触らない（CLAUDE.md の注意に従う）。
- **Rails の雛形**: ApplicationMailer・ApplicationJob・メーラーのレイアウトは、使うときの基底になるので残す。地図に「未使用の雛形」と書く。
- **補完監査の分**
  - 字幅の見積もり 2 系統（MorphemeCloud と ShareCardTypesetter）を統合する（A02-7。アクセント付き欧文の扱いを揃えると、配置が変わる）。
  - JSON のコピー欄を、JS が textarea から読む形にする（A04-4。いまは JSON を二重に埋め込んでいる）。
  - パーシャルのローカル変数の受け方を、全面的に strict locals に揃える（A04-14。新しいパーシャルの規則だけ §4.2 で決める）。
  - 五十音円環の描画（3 テンプレート）を KanaRing にまとめる（A05-6。共有カードの SVG のバイト列が変わると、og:image の URL が変わる）。
  - `top` というキーを改名する（A05-9・A02-6。テストの書き換えが要る）。
  - サンバーストのホバーの雛形を 1 本にする（A05-12。ブラウザでの確認が要る）。
  - `WordRequestDuplicateCheck.cache_key`（既存語の一覧のキャッシュ）のキーに版を付ける（§4.1 の既知の例外。P-02 の PR-12）。

### 7.8 この改修の目的の外にあるもの（性能）

可読性ではなく性能の問題。CLAUDE.md の「N+1 を作らない」に反しているので、改修とは別の PR で直すことを推奨する。

- A04-2: デッキで提案パネルを描くたびに、マスタ名を何度も DB に問い合わせている（20 枚で 150 回以上の見込み。未計測）。メモ化で減らせる。
- A05-11: 統計 §8 の実例を、特徴ごとに 1 クエリで引いている（N+1）。選ばれる実例を変えずに、1 本のクエリにできる。

## 8. 追加候補

計画外で見つけた問題は、台帳 [`LEDGER.md`](LEDGER.md) の §6「受付箱」に書く。初版のこの節の表は使わない。

## 9. 付録: 監査 ID と改修項目の対応

すべての指摘が、改修項目か §7 のどこかに対応している。

- **M**: M-01→C3-12 / M-02→D1-04・T0-13 / M-03→D1-12・G4-01 / M-04→C3-15 / M-05→C3-02 / M-06→D1-12（統合は §7.7） / M-07→D1-03 / M-08→D1-13 / M-09→§7.1 / M-10→C3-01 / M-11→C3-14 / M-12→C3-03（提案の取り込みは §7.1） / M-13→D1-13（統一は §7.7。intake のコメントは不採用） / M-14→C3-04（タイムアウトは §7.1） / M-15→R2-01・C3-13・D1-12 / M-16→D1-12・D1-03（読みの改行は §7.1） / M-17→C3-13・C3-01・C3-10 / M-18→C3-10・D1-13（race_condition_ttl は §7.1） / M-19→§7.7 / M-20→D1-13（設計の見直しは §7.2） / M-21→D1-13
- **C**: C-01→D1-14（修正は §7.1） / C-02→C3-14（ホームの数値は §7.1） / C-03→D1-14（修正は §7.1） / C-04→C3-10 / C-05→C3-16 / C-06→C3-17（llms の凡例は §7.1） / C-07→§7.1 / C-08→C3-10（ジャンル数は §7.5） / C-09→C3-08（マークアップは §7.7） / C-10→C3-09（描画は §7.7） / C-11→C3-18 / C-12→D1-12 / C-13→C3-07 / C-14→C3-07 / C-15→C3-05・G4-01（全面統一は §7.7） / C-16→R2-01・R2-02（エンジンのルートは §7.2、sessions は §7.1、雛形は §7.7） / C-17→C3-01・C3-20（インデックス可否の規則は §7.7） / C-18→C3-06（フッターのリンクは §7.1） / C-19→§7.3 / C-20→§7.1・D1-13（A-06 で確認済み） / C-21→G4-01（全面統一は §7.7） / C-22→C3-11・C3-05・D1-14（日付の書式は §7.7） / C-23→D1-14
- **J**: J-01→D1-15 / J-02→G4-03 / J-03→§7.1 / J-04→§7.1・§7.7 / J-05→C3-19 / J-06→D1-15（受け渡しは §7.7） / J-07→C3-20 / J-08→D1-15（パレットは §7.1） / J-09→D1-15（Turbo のキャッシュは §7.1） / J-10→§7.1 / J-11→D1-14（theme-color は §7.1、CSP は §7.2） / J-12→D1-09 / J-13→C3-19 / J-14→C3-19 / J-15→G4-03（/stats の移行は §7.1） / J-16→D1-15（統一は §7.7） / J-17→§7.1 / J-18→D1-15・D1-17 / J-19→R2-03・D1-15 / J-20→D1-15
- **S**: S-01→D1-09・§7.5 / S-02→D1-16・G4-03（移動は §7.7、公開ページで読まない件は §7.4） / S-03→C3-21・D1-16・R2-04 / S-04→R2-04（`.entry-row__go` は §7.1） / S-05→R2-04（font-weight は §7.7） / S-06→§7.4・§7.7 / S-07→D1-16・R2-04・C3-21（`--radius-sm` は §7.4、px のトークン化は §7.7） / S-08→T0-09・D1-14（パレットは §7.1） / S-09→C3-06 / S-10→D1-16 / S-11→§7.4 / S-12→D1-16 / S-13→D1-09
- **CFG**: CFG-01→D1-01（CI を待たせる件は §7.2） / CFG-02→C3-12・D1-04 / CFG-03→D1-03 / CFG-04→D1-03・T0-06（target の as_ci 化は §7.2） / CFG-05→D1-01 / CFG-06→§7.5 / CFG-07→C3-01・D1-12・D1-13 / CFG-08→D1-17・G4-03（解釈の変更は §7.1） / CFG-09→D1-02・D1-17 / CFG-10→D1-15 / CFG-11→D1-07・G4-03 / CFG-12→R2-02・G4-01（不足キーは §7.1、全面統一は §7.7） / CFG-13→G4-03（検証の追加は §7.1） / CFG-14→R2-05（rails/all は §7.2、Dockerfile は §7.5） / CFG-15→D1-17（分岐の削除は §7.2） / CFG-16→D1-17 / CFG-17→D1-17・R2-05 / CFG-18→D1-17
- **T**: T-01→T0-01 / T-02→D1-05・D1-17（3本の削除は §7.3） / T-03→T0-02 / T-04→T0-03・C3-01 / T-05→T0-04 / T-06→T0-11・C3-12・D1-17 / T-07→R2-06 / T-08→C3-22 / T-09→C3-23・D1-17 / T-10→D1-05（テストの分割は §7.3） / T-11→C3-11・R2-06 / T-12→T0-12 / T-13→§7.3 / T-14→C3-11 / T-15→C3-11・R2-01 / T-16→C3-04 / T-17→C3-11（文言は §7.3） / T-18→C3-11 / T-19→D1-17 / T-20→D1-17（棚卸し B-06）
- **DOC**: DOC-01→D1-01（CI を待たせる件は §7.2） / DOC-02→D1-02（README を含む） / DOC-03→D1-06（word-expansion-research を含む） / DOC-04→D1-03 / DOC-05→D1-04・C3-12 / DOC-06→D1-11 / DOC-07→G4-01・G4-03・D1-12 / DOC-08→D1-09・G4-03 / DOC-09→D1-05・C3-04（タイムアウトは §7.1） / DOC-10→C3-03・D1-06 / DOC-11→§7.5 / DOC-12→G4-01・G4-02 / DOC-13→D1-17・G4-03 / DOC-14→D1-06 / DOC-15→D1-07 / DOC-16→D1-01・D1-07・D1-12・D1-17・R2-01・R2-02（dev_samples は §7.5） / DOC-17→D1-05 / DOC-18→G4-03 / DOC-19→C3-04・C3-15・§4.8 / DOC-20→D1-06（DOC-17〜20 は棚卸し B-07）
- **SPEC**: SPEC-01→D1-08・G4-02 / SPEC-02→D1-09 / SPEC-03→D1-09・D1-16 / SPEC-04→D1-09・D1-16 / SPEC-05→D1-09・D1-16 / SPEC-06→D1-09 / SPEC-07→D1-14（定義の統一は §7.5） / SPEC-08→D1-11 / SPEC-09→D1-10 / SPEC-10→D1-08 / SPEC-11→D1-08・G4-02 / SPEC-12→D1-07・G4-03 / SPEC-13→D1-13・C3-01（モデルでの検証は §7.1） / SPEC-14→D1-07 / SPEC-15→D1-12・D1-14・D1-16 / SPEC-16→D1-08・D1-12・D1-17 / SPEC-17→D1-10 / SPEC-18→C3-01 / SPEC-19→§7.5 / SPEC-20→C3-01（color-mix は §7.4） / SPEC-21→D1-08 / SPEC-22→G4-02 / SPEC-23→D1-08 / SPEC-24→§7.3

補完監査（A-01〜A-11）の指摘も、すべて改修項目か §7 のどこかに対応している。

- **A01**: A01-1→D1-13・D1-15（検証は §7.1） / A01-2→§7.1 / A01-3→D1-10・D1-12（画面の文言は §7.1） / A01-4→D1-14（揃えるのは §7.1） / A01-5→D1-14 / A01-6→C3-01 / A01-7→C3-13
- **A02**: A02-1→D1-12（ログ・級数は §7.1） / A02-2→D1-10・D1-12 / A02-3→D1-12・D1-17 / A02-4→D1-12（値は §7.4） / A02-5→R2-04 / A02-6→R2-01・D1-12（`top` の改名は §7.7） / A02-7→D1-12（統合は §7.7） / A02-8→D1-12・D1-21 / A02-9→D1-12（判定を狭めるのは §7.1） / A02-10→D1-12・C3-01（ログは §7.1）
- **A04**: A04-1→§7.1・§7.5 / A04-2→§7.8 / A04-3→C3-07 / A04-4→C3-07（JS の変更は §7.7） / A04-5→C3-07・C3-01 / A04-6→D1-14（揃えるのは §7.1） / A04-7→C3-24 / A04-8→§7.1 / A04-9→C3-07 / A04-10→C3-07 / A04-11→C3-24 / A04-12→C3-24 / A04-13→R2-02・§7.5 / A04-14→§4.2・C3-07（全面統一は §7.7） / A04-15→§7.1
- **A05**: A05-1→§7.1 / A05-2→D1-10（配色は §7.4） / A05-3→D1-10・D1-16（揃えるのは §7.4） / A05-4→C3-01・D1-15・D1-16・T0-14 / A05-5→D1-21・D1-14 / A05-6→D1-14（まとめるのは §7.7） / A05-7→D1-10・D1-15 / A05-8→D1-10 / A05-9→R2-01（`price_bottom`・出来高の `count`）・D1-12（テストが参照する 2 つの `total`。PR-3）・R2-07・D1-14（改名は §7.7） / A05-10→D1-14（`.is-top` は §7.4） / A05-11→D1-10・§7.8 / A05-12→§7.7
- **A06**: A06-1→D1-13・§7.1 / A06-2→D1-13・§7.1 / A06-3→D1-13（422 にするのは §7.1） / A06-4→D1-12・§7.1 / A06-5→D1-14 / A06-6→D1-12 / A06-7→§7.1
- **A07**: A07-1→R2-07 / A07-2→R2-07 / A07-3→R2-07・D1-21・§4.4 / A07-4→D1-16（値域の検証は §7.1） / A07-5→D1-16・G4-03・§4.3
- **A08**: A08-1→C3-02・T0-10 / A08-2→D1-20・T0-10 / A08-3→D1-20・T0-10（使うようにするのは §7.1） / A08-4→D1-20 / A08-5→D1-20・D1-12 / A08-6→D1-13・§7.1 / A08-7→§7.1 / A08-8→C3-01・D1-13（SQL は §7.1） / A08-9→§7.1 / A08-10→D1-20・§7.5
- **A09**: A09-1→§7.5・D1-18（直す場合は §7.1） / A09-2→D1-18・D1-17 / A09-3→D1-13
- **A10**: A10-1→§7.5・D1-21（テストの式は §7.3、色は §7.4） / A10-2→D1-21（44px は §7.4） / A10-3→D1-21・§7.4 / A10-4→D1-21・§7.1 / A10-5→D1-21 / A10-6→D1-21（幅を減らすのは §7.4） / A10-7→D1-21・D1-14 / A10-8→C3-21・D1-21（余白は §7.4） / A10-9→D1-21 / A10-10→D1-21 / A10-11→D1-21・§7.1
- **A11**: A11-1→D1-19・§4.7 / A11-2→D1-19（正規化は §7.2） / A11-3→D1-19 / A11-4→D1-19 / A11-5→§7.5・D1-19 / A11-6→D1-19 / A11-7→D1-19 / A11-8→D1-19 / A11-9→D1-19（定義を広げるなら §7.5） / A11-10→D1-06 / A11-11→D1-19・§7.5 / A11-12→D1-19・§4.5（画面の文言は §7.1） / A11-13→D1-19

反証レビュー（P-02）の指摘も、すべて計画書に反映した。

- **PR**: PR-1→C3-18・T0-04 / PR-2→C3-13・§6・§7.2 / PR-3→R2-01・D1-12 / PR-4→§6 / PR-5→§4.7・§6・D1-09・D1-10・D1-21・G4-01・G4-02 / PR-6→T0-15・C3-14・C3-15・C3-16・D1-14・G4-04・§6 / PR-7→C3-01 / PR-8→R2-05・G4-04 / PR-9→C3-24・§3・§4.2 / PR-10→§0.2・C3-12 / PR-11→C3-04 / PR-12→§4.1・§4.2・C3-10・C3-20・§7.7 / PR-13→§6 / PR-14→§6・D1-01・R2-05 / PR-15→T0-16〜T0-21・§6・R2-04・C3-21 / PR-16→T0-02・C3-07・C3-11・C3-14・C3-19・R2-07・G4-02・§0.2・§4.1・§6

## 10. 承認のときに決めてほしいこと

1. この計画（区分 T0〜G4 の 78 項目）を進めてよいか。外したい項目があれば ID で指定してほしい。とくに次の 2 点は、オーナーの作業や例外を伴う。
   - C3-12 は、運用タスク（backfill）の欠陥を直すので、rake が書く値と出力が変わる（§0.2 の例外）。これを含めてよいか。
   - 第5群の途中（C3-12 の後）で一度 merge し、本番で `bin/rails backfill:verify` を流してもらう必要がある（§6。P-02 の PR-2）。
2. §7.5 の各項目の判断。この改修ではどれも実施しないが、次の 2 つは、文書の書き方が回答で決まる。
   - A09-1（公開の取り消しの遅れ）: 許容するなら D1-18 で文書に書く。許容しないなら第7群で直す。
   - A10-1（ΔRGB の式）: D1-21 で design.md に書く式が決まる。
3. D1-09・D1-21 の方針（実装を正として design.md を直す。見た目は変えない）でよいか。文書のほうを正としたい項目があれば指定してほしい。
4. §7.1 の振る舞いの変更（不具合の修正を含む）を、改修の後に第7群として、1 件 1 PR で直すか。直すならどれか。
   確認済みの不具合で、直す価値が高いと考えるものは次のとおり（推奨）。
   - A04-1: 管理画面の「日本語のみ」の絞り込みが外れない（直すのは 1 行）。
   - C-01: /words から「条件を変える」で /search へ移ると、条件の一部が落ちる。
   - C-03: ログイン中だけの差分がある HTML を、public で HTTP キャッシュしている。
   - J-17: コピーボタンを 2 秒以内に 2 回押すと、「コピーしました」のまま戻らない。
   - A05-1: 統計 §8 のリード文の「下線」が、実装と違う。
5. 監査の記録（`docs/refactoring/audits/`）をリポジトリに残してよいか（改修が終わったら docs/history/ へ移す）。
