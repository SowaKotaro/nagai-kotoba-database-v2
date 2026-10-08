> フェーズ1の監査報告（担当: db・config・lib・CI）。行番号は `a04f375` 時点のもので、**現行の仕様ではない**。
> 統合と採否は [`../ai-legibility-plan.md`](../ai-legibility-plan.md) を参照。

# 監査報告 CFG（db / config / lib/tasks / script / tools / bin / CI・デプロイ）

実行したのは読み取り系のコマンドと `bin/rails routes` だけです。ファイル・git・DB・テストには触れていません。

## 指摘（重要度の高い順）

### [CFG-01] main へのマージがそのまま本番デプロイになり、CI を待たない。このことが CLAUDE.md と overview に書かれていない
- 観点: A・E ／ 確度: 確認済み
- 根拠:
  - `.github/workflows/deploy.yml:3-6`（`on: push: branches: - main`）と `:35`（`run: bundle exec cap production deploy`）。`needs:` も `workflow_run` も無く、ci.yml に依存していない。
  - `ci.yml:3-7` は PR 時と main への push 時に動く。つまり main への push では CI とデプロイが同時に走る。
  - `CLAUDE.md:20`「デプロイ: **Capistrano**（`cap production deploy`）」、`CLAUDE.md:23`「CI: …PR 作成時 と main への push 時 に実行」。`docs/overview.md:41-42` も同じ内容で、deploy.yml には触れていない。
  - CI の通過を確認する仕組みは手順の中だけにある: `.claude/commands/cppmtm.md:30`「CI を待って merge: `gh pr checks <番号> --watch`」。
- 問題: docs を読んだエージェントは「デプロイは人が cap を叩いたときだけ」と誤解する。main 上の CI が落ちてもデプロイは止まらない。
- 提案: CLAUDE.md の「デプロイ」「CI」の行と overview §2 に、次の3点を書く。
  - deploy.yml は main への push で `cap production deploy` を自動で実行する。
  - CI の完了は待たない。
  - 関門は PR 上の CI と cppmtm の手順だけ。
  deploy.yml の冒頭にも同じ内容をコメントで置く。CI を待つように変える案は計画書への提案だけにとどめる。
- 影響ファイル: CLAUDE.md, docs/overview.md,（任意で）.github/workflows/deploy.yml のコメント
- リスク: 文書だけなら低。ワークフローの挙動を変えるなら高 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要
- 別枠（未コミットの作業中の変更）: 作業ツリーの README.md には「`deploy.yml`: main への push で Capistrano による本番デプロイ」という行が足されている（HEAD には無い）。

### [CFG-02] backfill の修復と検査が派生列の一部しか扱わない。派生列の一覧も3箇所に分かれている
- 観点: C・D・A ／ 確度: 確認済み（ring_crossing_count の欠落は親も確認済み）
- 根拠:
  - `app/models/word_sense.rb:148-156` の `assign_reading_derivations` は `ring_crossing_count` も算出している（:153）。
  - `lib/tasks/backfill.rake:7` の desc「(rhythm_pattern/vowel_pattern/mora_count/last_char)」、`:12-17`（update_columns）、`:46-51`（verify）のどれにも `ring_crossing_count` が無い。この列は 2026-07-21 に追加された。
  - verify は words の代表値 14 列（`schema.rb:193-210` のうち min_*/max_*/sense_count/variant_count/feature_count）を検査していない。それなのに `CLAUDE.md:40-41` は「`backfill:verify` で差分を検出し … `backfill:sense_metrics` で直す」と書いている。
  - `backfill.rake:12` は `update_columns` を使うのでコールバックを通らない。そのため mora_count などを直しても、words 側の `max_mora_count` などは sense_metrics を流すまで古いまま。タスクもそのことを出力しない。
  - `docs/data-model.md:69` は STORED 生成カラムについて「DB が値を保証するので、直接 UPDATE しても狂わない」と書く。しかし `words.reading_density`（`schema.rb:205`）は、after_commit で焼き直す `max_reading_length` に依存している。
  - `app/models/word_sense_metrics.rb:108` のコメント「実行される UPDATE 文(テストと backfill から参照する)」は事実と違う。実際に呼んでいるのは同じファイルの `:105` だけ。
- 問題: `ring_crossing_count` や代表値がずれても、verify は「不整合はありません」と答える。新しい派生列を足すときは 3 箇所を直す必要があるが、そのことが分からない。実際に1回漏れている。
- 提案:
  - 読みから導く値を1箇所で返すメソッドを作る（例 `WordSense.reading_derivations(reading)`）。before_validation、reading_metrics、verify の3つがそれを使う。
  - verify に、WordSenseMetrics の集計 SQL と words の列の突き合わせを足す。
  - reading_metrics の最後に `WordSenseMetrics.refresh!` を呼ぶ。呼ばないなら、sense_metrics を続けて流すよう出力で案内する。
  - desc、data-model.md §3.1、word_sense_metrics.rb:108 を実態に合わせて直す。
- 影響ファイル: lib/tasks/backfill.rake, app/models/word_sense.rb, app/models/word_sense_metrics.rb, docs/data-model.md, CLAUDE.md, test/tasks/backfill_task_test.rb
- リスク: 低〜中 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト:
  - 既存: `test/tasks/backfill_task_test.rb` が次の3点を固めている。reading_metrics が rhythm/vowel/mora/last_char を直すこと。verify が last_char と char_type_pattern のずれを報告すること。不整合 0 件のとき何も変えないこと。
  - 追加するもの: ① ring_crossing_count を壊すと verify が報告し、reading_metrics が直すこと ② words の代表値を壊すと verify が報告すること。
  - 既存テストへの影響: フィクスチャは全語義に ring_crossing_count を持っている（`test/fixtures/word_senses.yml:14,25,35,44`）。`test/test_helper.rb:18` も毎回 refresh! している。そのため「不整合なし」のテストは保たれる見込みだが、実行しての確認はしていない。

### [CFG-03] CLAUDE.md の as_ci 列の一覧が schema.rb と一致しない
- 観点: A ／ 確度: 確認済み
- 根拠: `CLAUDE.md:46-48` の一覧に `word_candidates.surface` / `original_surface`（`schema.rb:80,85`、as_ci）が無い。`docs/data-model.md:170` には入っていて正しい。STORED 生成カラム4本（CLAUDE.md:31-32 と schema.rb:161,168,205,208）とテーブル数 16 は一致している。
- 問題: CLAUDE.md だけを見たエージェントは、word_candidates を ai_ci の表だと思い込む。
- 提案: CLAUDE.md では列を列挙せず「正は data-model.md §6（その正は schema.rb）」と参照だけ置く。列挙を残すなら word_candidates を足す。
- 影響ファイル: CLAUDE.md ／ リスク: 低 ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: 不要

### [CFG-04] 照合順序が一意制約と文字種検索にどう効くかが書かれていない
- 観点: E ／ 確度: 推測（照合順序の仕様と data-model.md:160 の記述から導いた。DB で実行して確かめてはいない）
- 根拠:
  - `schema.rb:228` の `uq_words_surface`、`:91`（word_candidates）、`:154`（別表記）はどれも as_ci。data-model.md:160 は as_ci について「ひらがな⇔カタカナ・A⇔a の同一視は残る」と書くが、検索の話としてしか書いていない。
  - `schema.rb:191` の `char_type_pattern` は ai_ci のまま。`word_sense.rb:98-99` のコメントは「A=a とみなす」としか言わないが、実際は「あ」と「ア」も同じ扱いになる。大小を区別しない検索（`word_sense_search.rb:81`）で影響が出る。
  - `schema.rb:129-130` の `word_sense_features.target` / `target_reading` は表層形・読みの一部なのに ai_ci のまま。CLAUDE.md:48 の規則（読み・表層形の列は as_ci）の例外として記録されていない。
  - マスタ名の UNIQUE（`schema.rb:36,46,54,61,99`）は ai_ci なので、清濁だけが違う名前は作れない。
- 問題: 「ハンバーガー」と「はんばーがー」のように、かなの種類や大小・全半角だけが違う表層形は別の語として登録できない。エージェントがこれをバグとみなして照合順序を変えてしまうおそれがある。
- 提案: data-model.md §6 に次の3点を足す。スキーマは変えない。
  - 一意制約にも同じ同一視が効くこと。
  - target 列が ai_ci のままになっている経緯（as_ci の規則より前に作られた）。
  - char_type_pattern では あ=ア になること。
  あわせて word_sense.rb:98-99 のコメントを直す。
- 影響ファイル: docs/data-model.md, app/models/word_sense.rb ／ リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 文書化の前に次の2つのテストで実態を固める。① かなの種類だけが違う surface の Word が uniqueness で弾かれる ② `char_type_pattern_matching("アアア", partial: false, case_sensitive: false)` がひらがなの語に当たり、`case_sensitive: true` では当たらない。

### [CFG-05] 本番への副作用と「本番では使われない設定」が、コード側に書かれていない
- 観点: A・E ／ 確度: 確認済み
- 根拠:
  - `config/deploy.rb:59` の desc は「管理者(seed)を作成/更新する」としか言わない。実際には `db/seeds.rb:31` の `SeedCatalog.seed_all!` も走り、`seed_catalog.rb:285-300` の RENAMES で本番のマスタが改名される。`deploy.rb:71` により、これが毎回のデプロイで実行される。
  - 本番では使われない設定が3箇所ある: `deploy.rb:54-56` の default_env、`config/database.yml:60-64` の production ブロック、`deploy.yml:33-34` のシークレット受け渡し。「本番では使われない」という説明は `CLAUDE.md:21-22`、`overview.md:215-218`、`issues.md:479`（確定事項 28）にしかない。
- 問題: deploy.rb だけを読むと、SeedCatalog を変えると次のデプロイで本番データが書き換わることに気づけない。また production ブロックを直しても何も効かない。
- 提案: desc を「管理者とマスタ（RENAMES による改名を含む）を冪等に投入」に直す。3箇所に「本番では未使用（確定事項 28）」とコメントする。値の削除は計画書への提案だけにする。
- 影響ファイル: config/deploy.rb, config/database.yml, .github/workflows/deploy.yml
- リスク: 低（コメントのみ。ただし CLAUDE.md:219 に従い、変更前に説明する） ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: 不要（`test/models/seed_catalog_test.rb:124` が冪等性を固めている）

### [CFG-06] 開発用ダミーデータが2系統あり、docs が挙げている方の語は公開面に出ない
- 観点: A・B・C ／ 確度: 確認済み
- 根拠:
  - `db/seeds.rb:35` は development で `db/seeds/development.rb` を自動で読み込む。こちらは `db/seeds/development.rb:42` で `word.mark_annotated` を呼ぶので、公開状態の語になる。
  - `lib/tasks/dev_samples.rake:94` は `Word.find_or_create_by!(surface: ...)` で、annotated_at を立てない。公開されるのは annotated_at がある語だけ（`data-model.md:200`）。このタスクは 2026-07-03（fd07707）に作られ、公開の限定は 07-05（b967043）に入った。
  - `dev_samples.rake:9` の `"名詞"` は SeedCatalog（`seed_catalog.rb:221-225`）に無い品詞名。`:60` の「セイブツ」など、読みが 10 字未満の語もある（`word_sense.rb:33` の MIN_READING_LENGTH = 10 に反する）。
  - `docs/overview.md:168` は dev:sample_data だけを「デザイン確認用」として紹介し、development.rb には触れていない。
- 問題: dev:sample_data を流しても公開ページには何も出ず、開発 DB にだけ SeedCatalog の外のマスタが増える。どちらが正典か分からない。
- 提案: development.rb を正典にする。dev:sample_data は、mark_annotated を付ける・マスタ名を SeedCatalog に揃える・読み 10 字以上の語に差し替える、のいずれか（または全部）で直すか、廃止する。overview §7 に両方の役割を書く。
- 影響ファイル: lib/tasks/dev_samples.rake, docs/overview.md ／ リスク: 低 ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: なし（開発用タスク）

### [CFG-07] SeedCatalog のマスタ名とコードが暗黙に結びついている。モデルのコメントもカタログと食い違う
- 観点: E・A ／ 確度: 確認済み
- 根拠:
  - `word_sense.rb:37` に `JAPANESE_ORIGIN_NAME = "日本語".freeze` がある。これは `seed_catalog.rb:202` の語種名と一致している前提で動く。RENAMES（`seed_catalog.rb:8-9`）で「日本語」を改名すると、`with_japanese_origin`（`word_sense.rb:130-133`）は黙って 0 件を返すようになる。この前提を固めるテストは無い（`test/fixtures/word_origins.yml:3` に注記があるだけ）。
  - `word_origin.rb:2` は「(和語 / 漢語 / 英語 …)」、`word_sense_origin.rb:3` は「歯ブラシ = 和語 + 英語」と書くが、カタログの名前は「日本語」。
  - 整合が取れている点: 用語解説とカタログの 1:1 は `test/models/linguistic_feature_glossary_test.rb:6` で担保されている。`docs/genres.md` の中分類 151 件は SeedCatalog::GENRES と一致する（diff で確認）。
- 提案: 名前の定数を SeedCatalog に置き、WordSense からそれを参照する。「定数がカタログに含まれる」ことを確かめるテストを足す。2つのコメントを直す（マイグレーション内のコメントは触らない）。
- 影響ファイル: app/models/word_sense.rb, seed_catalog.rb, word_origin.rb, word_sense_origin.rb, test/models/seed_catalog_test.rb
- リスク: 低 ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: 既存は `test/models/feature_research_export_test.rb:70`。上の包含テストを先に足す。

### [CFG-08] 環境変数の docs（overview §8）とコードの照合
- 観点: A・B・E ／ 確度: 確認済み
- 根拠:
  - docs にあってコードに無い変数は無い。§8 の変数はすべて読まれている（application.rb:49,54,58-59、application_helper.rb:61,70-71、reading_extractor.rb:64、database.yml、deploy.rb:55、seeds.rb:15-16、puma.rb:9、stats.rake:51）。
  - コードにあって docs に無い変数:
    - `production.rb:65` の RAILS_LOG_LEVEL
    - `puma.rb:1-2` と `database.yml:15` の RAILS_MAX_THREADS / RAILS_MIN_THREADS
    - `puma.rb:19-20` の PORT / PIDFILE
    - `test.rb:18` の CI
    - `test/application_system_test_case.rb:14` の CHROME_BIN
    - `cable.yml:9` の REDIS_URL（ただし未使用）
    - `deploy.yml:24,29` のシークレット SSH_PRIVATE_KEY / KNOWN_HOSTS
  - 真偽値の解釈が変数ごとに違う: `application.rb:54` は `ENV["INDEXING_ENABLED"].present?` なので、`=false` と設定しても解禁になる。`:58-59` の REQUESTS_ENABLED は Boolean として解釈する。
  - 読む場所も2通りある: `config.x` と、ヘルパーでの ENV 直読み（application_helper.rb:61,70-71）。
  - `overview.md:230-231` は「実行方法は CLAUDE.md とセッションのメモを参照」と書くが、CLAUDE.md（:212）にはコマンドしかなく、CHROME_BIN の説明も無い。
  - MECAB_DICT が効くのは ReadingExtractor だけ（`morpheme_extractor.rb:58` は既定辞書で固定）。
- 提案:
  - §8 に「Rails・Puma 標準」「テスト用」「Actions のシークレット」の欄を足す。
  - INDEXING_ENABLED は値を見ないことを、docs と application.rb:54 のコメントの両方に書く。解釈を揃える変更は、本番での値が分からないので計画書への提案だけにする。
  - 正典は「アプリのスイッチは application.rb で config.x に読む」（application.rb:51-59 を手本にする）。
- 影響ファイル: docs/overview.md, config/application.rb, CLAUDE.md ／ リスク: 低（解釈を変えるなら中） ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: 解釈を変えるときだけ（`test.rb:67` が言及する indexing_switch_test の中身は未確認）

### [CFG-09] 「ローカルで通れば CI も通る」が成り立たない。マイグレーションは CI で一度も流れない
- 観点: A・E ／ 確度: 確認済み（db:prepare が新しい DB でスキーマを読み込む点だけは推測）
- 根拠:
  - `CLAUDE.md:53` は「ローカルで通れば CI も通る」と書く。しかし `test.rb:18` は `config.eager_load = ENV["CI"].present?` で、eager load は CI でしか効かない。
  - `ci.yml:109` は `db:test:prepare`（schema.rb の読み込み）を使う。一方でマイグレーションはアプリのコードを呼んでいる: `20260721103000_...:26` の `KanaRing.crossing_count`、`20260806100000_...:77` と `:96` の `WordSenseMetrics`。
  - `overview.md:161` は `db:prepare` を「DB 作成 → マイグレーション → seed」と書くが、新しい DB ではマイグレーションではなくスキーマの読み込みになる。
- 問題: ゼロからの `db:migrate` が壊れても誰も気づかない。ローカルで通っても CI で落ちることがある。
- 提案: CLAUDE.md に「CI と同じ条件で試すには `CI=1 bin/rails test test:system`」と書く。docs に「新しい環境は db:prepare（スキーマ読み込み）で作る。ゼロからの db:migrate は保証しない」と書く。マイグレーション自体は書き換えない。
- 影響ファイル: CLAUDE.md, docs/overview.md, docs/data-model.md ／ リスク: 低 ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: 不要

### [CFG-10] importmap のコメント「公開ページではコントローラを使わない」が事実と違う
- 観点: A ／ 確度: 確認済み
- 根拠: `config/importmap.rb:7` と `app/javascript/controllers/index.js:2` がそう書いている。しかし全ページ共通のヘッダーが3つのコントローラを使う: `shared/_header.html.erb:4`（nav-drawer）、`:41`（nav-menu）、`:79`（theme）。ほかにも `words/show.html.erb:52` や `stats/_vowel_graph.html.erb:11` が使う。importmap.rb の最終変更は 2026-07-05（11b971c）。
- 提案: preload しない理由を「data-controller が現れたときだけ遅延読み込みするため。公開ページでもヘッダーの3つは毎回読み込まれる」に書き直す。挙動は変えない。
- 影響ファイル: config/importmap.rb, app/javascript/controllers/index.js ／ リスク: 低 ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: 不要

### [CFG-11] docs の参照切れと、コードの地図の欠け
- 観点: A ／ 確度: 確認済み
- 根拠:
  - `data-model.md:182` と `:191` は「issues.md Issue 56」を参照するが、Issue 56 はクローズ済みで issues.md に残っていない（`issues.md:485`、実体は `changelog.md:292`）。
  - `CLAUDE.md:221` の「issues.md Issue 80・81」も、実体は `changelog.md:145-163` にある。
  - `overview.md:118-152` のコードの地図に、次のファイルが無い: bulk_word_registration / word_batch / word_window の各モデル、concerns の refreshes_word_metrics / tag_master、candidates.css（CSS を列挙している :39 と :143 にも無い）。
  - `.gitignore:40` のコメントは調査スキルを3つしか挙げていない。
- 提案: 参照先を changelog に張り替え、地図に足りないファイルを足し、.gitignore のコメントを一般化する。
- 影響ファイル: docs/data-model.md, CLAUDE.md, docs/overview.md, .gitignore ／ リスク: 低 ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: 不要

### [CFG-12] locales: キーの引き方と置き場所の規則が2通り混在している
- 観点: B・A ／ 確度: 確認済み（未定義キーが実際に画面に出る経路は推測）
- 根拠:
  - 引き方: ビューでは絶対キーが 874 件、遅延参照（`t(".…")`）が 105 件。遅延参照は word_requests/new、admin/word_requests、admin/candidates、admin/word_candidates に集中している。
  - 置き場所の例外:
    - `ja.yml:222-287` の `searches` は、ビューの階層（searches/index）に対応しない平置き。
    - `:150` の `layouts` は shared のパーシャルから使われている。
    - `:489` の `admin.word_candidates` と `:618` の `admin.candidates` が並んでいる。
    - `:106-107` の `labels.en` は理由のコメントがあるので問題なし。
  - `ja.yml:19-28` の errors.messages には、`word_sense_feature.rb:18` が使う `greater_than_or_equal_to` が無い。rails-i18n も入っていない。
  - `en.yml:30-31` は `hello: "Hello world"` のまま。`application.rb:45` の `:en` はどこからも使われていない。
- 提案: 正典は「ビューのパスに一致するキーを絶対キーで引く」（多数派で、grep で辿れる）。画面をまたいで使う語彙は名前付きの共有枠に置く。既存の遅延参照は、その画面を触るときに寄せる。この規則を CLAUDE.md に1文で足し、不足しているキーを足す。
- 影響ファイル: config/locales/ja.yml, en.yml, config/application.rb, CLAUDE.md ／ リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 先に test 環境で `raise_on_missing_translations` を有効にする（`test.rb:56-57` はコメントアウトされている）

### [CFG-13] DB の NOT NULL / UNIQUE とモデルの validates が、片方にしか無い箇所
- 観点: A・B ／ 確度: 確認済み
- 根拠（CLAUDE.md:89 は「両方で担保する」と定めている）:
  - DB にしか無い制約:
    - `admins.username`（`schema.rb:18-19`。`admin.rb` は normalizes だけ）
    - `annotation_proposals.word_id` の UNIQUE（`schema.rb:29`）
    - `genres.level` の NOT NULL（`genre.rb:4` は enum だけ。`:79` で `return if level.blank?`）
    - `word_candidates.original_surface`（`word_candidate.rb:128` の `||=` だけ）
    - 長さ 768 の surface / reading / target の各列（モデル側に長さの検証が無い）
    - word_requests の長さ上限。モデルではなく `word_requests_controller.rb:125-127` の `slice(0, 512/1024)` に直書きされている
  - モデルにしか無い制約（docs に書かれていないもの）: `word_sense_feature.rb:22-23`、`word_request.rb:23`、`word_candidate.rb:62-63`、`word_request_item.rb:16-18`（DB の上限より厳しい）
  - enum で `validate: true` を使っているのは `word_candidate.rb:29-32` だけ。`word.rb:15`、`word_request_item.rb:14`、`annotation_proposal.rb:13` は付けていない。
- 提案: data-model.md §7 に「片方だけの制約」の表を置く。長さの上限はモデルの定数に移す。enum は `validate: true` を正典にする。Admin / AnnotationProposal に uniqueness を足す件は提案だけにとどめる。
- 影響ファイル: docs/data-model.md, 該当モデル, word_requests_controller.rb ／ リスク: 低〜中 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 長い User-Agent が切り詰めて保存されることのテストがあるかは未確認

### [CFG-14] Rails の雛形の残骸（使われていない設定・ファイル・フレームワーク）
- 観点: C ／ 確度: 確認済み（`/cable` のマウントだけ推測）
- 検索したパターン: `perform_later|deliver_later|ActionCable|turbo_stream_from|broadcast|has_one_attached|has_many_attached|ActiveStorage|rich_text|locale: :en|with_locale|staging`
- 根拠:
  - Action Cable: `cable.yml:7-10` は redis 前提だが、redis の gem はコメントアウトされている（Gemfile:29-30）。app/channels にも利用が無い。
  - Active Storage: `storage.yml`、`production.rb:40`、`development.rb:37`、`deploy.rb:17` に設定があるが、利用もテーブルも無い。
  - `application.rb:3` の `require "rails/all"` のせいで、テーブルの無い action_mailbox / conductor / active_storage のルートが生えている（`bin/rails routes` で確認）。
  - app/jobs、app/mailers、layouts/mailer.* は、ジョブもメールも無いのに残っている。
  - デプロイ: `config/deploy/staging.rb` は全行コメント。`Capfile:43` の glob 先 `lib/capistrano/tasks` は存在しない。
  - Dockerfile / bin/docker-entrypoint / .dockerignore は、docs のどこにも言及が無い（grep で 0 件）。
  - CSP: `content_security_policy.rb` と `permissions_policy.rb` は全行コメントなのに、`layouts/application.html.erb:7` は `csp_meta_tag` を出している。
  - 雛形の英語コメント: `routes.rb:141-147`、`db/seeds.rb:1-9`、`deploy.rb:8-9,21-47`。
- 提案:
  - ① 無害な削除: staging.rb、Capfile の glob、雛形コメント、en.yml の hello、Dockerfile 一式。
  - ② `rails/all` を、実際に使うフレームワークだけの require に絞る。**計画書への提案のみ**。turbo-rails が Action Cable 無しで eager load できるかを確かめる必要がある。
- 影響ファイル: config/application.rb, config/environments/*, cable.yml, storage.yml, staging.rb, Capfile, Dockerfile ほか
- リスク: ①は低、②は中〜高 ／ 外部振る舞いへの影響: ①はなし。②はあり（フレームワーク既定の `/rails/*` が 404 になる。アプリの公開 URL は変わらない）
- 先に必要な特性テスト: ②の前に、production 相当（eager_load 有効）で起動し、公開ページと og:image が今と同じ応答を返すことを確かめるスモークテスト

### [CFG-15] puma.rb: 効果の無い分岐と、値の重複（コメントが無い）
- 観点: A・C・D ／ 確度: 推測（Puma の仕様からの判断。起動して確かめてはいない）
- 根拠:
  - `config/puma.rb:10-14`（`if worker_count > 1 … else preload_app!`）: preload_app! はクラスタモードでしか意味を持たず、しかも Puma 5 以降はクラスタモードで既定で有効。単一モードの分岐で呼んでも何も起きない。
  - `:16-17` のパスは `deploy.rb:12` の deploy_to と同じ値の直書き。
  - `:21` の `worker_timeout 3600` には理由が書かれていない。
- 提案: コメントを足すだけにする。分岐の削除は計画書への提案だけ。
- 影響ファイル: config/puma.rb ／ リスク: 高（インフラ設定で、デプロイ時に再起動を伴う） ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: なし（本番での起動で確認する）

### [CFG-16] routes.rb に「公開 URL を変えない」方針が書かれていない
- 観点: A・E ／ 確度: 確認済み
- 根拠: この方針は `CLAUDE.md:217` にしか無い。`routes.rb` には公開と管理の区切りを示す見出しが無く、公開側の `root` と `/up`（:143-148）が admin の後ろに置かれている。`:56` の「3ステップ」の説明に `:60` の apply_research が出てこない。
- 提案: 冒頭に「公開面（URL とクエリパラメータ名は変更不可）／管理面」の見出しコメントを置き、apply_research を説明に足し、雛形コメントを削除する。
- 影響ファイル: config/routes.rb ／ リスク: 低 ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: ルートを並べ替えるなら、`bin/rails routes` の出力を前後で比べる

### [CFG-17] lib/tasks の小さなずれ
- 観点: C・E ／ 確度: 確認済み（本番に MeCab が無いこと自体は推測）
- 根拠:
  - `stats.rake:50` はトップレベルで `def load_surfaces` しているので、Object 全体にメソッドが生える。
  - `stats.rake:3` の「本番・CI には MeCab が無い」という前提が、docs の外部コマンドの表（`overview.md:172-178`）に書かれていない。
  - `backfill.rake:1-3` の冒頭コメントは 2026-07 時点の経緯のまま。
- 提案: load_surfaces をラムダにする。overview の外部コマンドの表に「本番での有無」の列を足す。冒頭コメントを今の用途に合わせて書き直す。
- 影響ファイル: lib/tasks/stats.rake, backfill.rake, docs/overview.md ／ リスク: 低 ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: 不要

### [CFG-18] マイグレーションの残骸と古い参照（マイグレーションは書き換えず、docs で説明する）
- 観点: C・A ／ 確度: 確認済み（INSTR / LOCATE の説明の正誤は推測）
- 根拠:
  - `20260629132054_create_articles.rb` と `20260630152904_drop_articles.rb` は、どの docs にも説明が無い（grep で 0 件）。
  - `20260806100000_...:83` の「(CLAUDE.md「生成カラム」参照)」は、そういう見出しが CLAUDE.md に無い。
  - `20260708100000_...:16` の「LOCATE は…文字位置を返すので INSTR を使う」は理由として成り立っていない（どちらも文字位置を返す）。
  - `20260704100100_...:3` の「和語 / 漢語」は、現在のカタログの名前と違う。
- 提案: data-model.md に「db/migrate のコメントは当時の記録。現行の仕様の正は schema.rb と本書。articles の2本は初期の雛形の試し」と1段落足す。
- 影響ファイル: docs/data-model.md ／ リスク: 低 ／ 外部振る舞いへの影響: なし ／ 先に必要な特性テスト: 不要

---

## 1. この領域の正典パターン案
- **派生値**: 手本は `app/models/word_sense_metrics.rb`。SQL の定数が唯一の正で、after_commit、マイグレーション、backfill:sense_metrics がすべてここを呼んでいる。読み由来の Ruby 側の派生値も同じ形にし、backfill.rake はモデルを呼ぶだけにする（`backfill.rake:23-29` が手本）。
- **マスタ名**: `app/models/seed_catalog.rb` を唯一の正にする。コードで名前を使うときはカタログの定数を参照し、テストで固める（`test/models/linguistic_feature_glossary_test.rb:6` が手本）。
- **読み・表層形の列**: `collation: "utf8mb4_0900_as_ci"` を明示し、理由を一言コメントする（`db/migrate/20260924100000_create_word_candidates.rb:9-11` が手本）。列の一覧は data-model.md §6 だけに置く。
- **環境変数**: application.rb で1回だけ読み、`config.x` に置く。真偽値は Boolean として解釈する（`config/application.rb:51-59` が手本）。
- **rake タスク**: desc には実際に触る列をすべて書く。規則はモデルに任せる。トップレベルで def しない。冪等にする。
- **開発データ**: `db/seeds/development.rb` を正典にする。
- **i18n**: ビューのパスに一致するキーを絶対キーで引く。
- **デプロイと CI**: 「何が、いつ、何を待って走るか」を CLAUDE.md の1箇所にまとめる。

## 2. コードに表明すべき暗黙の前提
1. main への push で本番デプロイが走り、CI は待たない。
2. 本番の DB 接続はサーバ上の database.yml が持つ。リポジトリの production ブロック、default_env、deploy.yml の env は使われない。
3. deploy:seed は毎回のデプロイでマスタを投入し、RENAMES による改名も行う。管理者のパスワードも毎回かけ直す（`seeds.rb:19-21`）。
4. as_ci は、かなの種類・大小・全半角を同じ文字とみなす。そのため words、word_candidates、別表記の UNIQUE でも、それらだけが違う表層形は同じ値として衝突する。
5. char_type_pattern は ai_ci なので、大小を区別しない検索では あ=ア になる。
6. word_sense_features の target / target_reading は ai_ci のまま（as_ci の規則ができる前の列）。
7. マスタ名の UNIQUE は ai_ci なので、清濁だけが違う名前を作れない。
8. reading_density は STORED 生成カラムだが、after_commit で焼き直す max_reading_length に依存する。
9. backfill:reading_metrics はコールバックを通らない。words の代表値は sense_metrics で別に直す必要がある。
10. 一部のマイグレーションは現行のモデルを呼ぶ。CI はマイグレーションを流さない。新しい環境はスキーマの読み込みで作る。
11. テストで eager load が効くのは、環境変数 CI があるときだけ。
12. INDEXING_ENABLED は値を見ない。設定されていれば解禁になる。
13. JAPANESE_ORIGIN_NAME は、SeedCatalog の語種名「日本語」と一致している前提で動く。
14. 本番には MeCab が無い（`stats.rake:3` にだけ書かれている）。
15. 用語解説の YAML と形態素頻度の JSON は、プロセスごとに1回だけ読まれる。形態素頻度は 2026-09-10 時点・1,476 語で集計した固定データで、更新はローカルで手で行う。
16. development で db:seed を流すと、公開状態のダミー語が大量に入る。
17. preload_app! は単一モードでは効かない。ソケットのパスは deploy_to と一致させる必要がある。
18. キャッシュは `:memory_store`（`production.rb:69`）なので、WEB_CONCURRENCY を上げるとキャッシュも rate_limit もプロセスごとに分かれる。このことは設定ファイルに書かれていない。

## 3. コメントの傾向
- この領域の独自コメント（日本語）は「なぜ」をよく書いている。マイグレーション、application.rb、seed_catalog.rb、WordSenseMetrics がその例。
- 「何をしているか」だけのコメントは、目で見た概算で独自コメントの2〜3割。
- むしろ問題なのは次の2点:
  - Rails の雛形の英語コメントがそのまま大量に残っている（staging.rb 全 61 行、production.rb、deploy.rb、storage.yml、initializers の大半）。
  - 説明が要る設定にコメントが無い（puma.rb 全体、cable.yml、Dockerfile の位置づけ）。
- 「何をしているか」だけのコメントの例:
  - `config/routes.rb:25`「50音・読みの文字数の索引(ブラウズ導線)。Issue 22。」
  - `app/models/seed_catalog.rb:269`「全マスタを冪等に投入する(db/seeds.rb から呼ぶ)。」
  - `db/seeds.rb:28`「マスタ(ジャンル・語種・品詞・言語学的特徴)を投入する。」
  - `lib/tasks/dev_samples.rake:8` と `:40`「--- マスタ ---」「--- 単語(語義・特徴つき) ---」
  - `config/deploy.rb:70`「マイグレーション完了後に seed を自動実行する。」

## 未確認のまま残した範囲
- 本番の実際の値や状態（WEB_CONCURRENCY、INDEXING_ENABLED の値、MeCab の有無、MySQL の版、systemd の override.conf）。
- GitHub のブランチ保護（main への直接 push の禁止、必須チェックの有無）。CFG-01 の結論はこれに左右される。
- `/cable` の内部マウントの有無。rails/all を絞ったときに turbo-rails が eager load できるか。
- Puma 8 の単一モードで preload_app! が本当に効かないか。
- 新しい DB での db:prepare の実際の動きと、ゼロからの db:migrate が今も通るか（どちらも実行していない）。
- CFG-04 の照合順序の帰結を、DB で実行して確かめること。
- ja.yml の未使用キー（ビュー担当に任せた）。errors.messages の不足キーが実際に画面に出る経路。
- indexing_switch_test の中身。User-Agent の切り詰めを確かめるテストの有無。
- `script/og_default.py:56-58` の RING 座標が、現行の KanaRing.path の出力と一致するか（色が tokens.css と一致することは確認した）。
- `tools/claude-ai-skill/build.sh:35-37` の description と、`.claude/skills/word-reannotation-research/SKILL.md` の description が一致するか。
- `docs/annotation-guidelines.md` とマスタの記述の突き合わせ（§7 の参照だけ確認した）。
- research/README.md と .gitignore の細かな対応。
- `test/application_system_test_case.rb:26-28` の Google Fonts 遮断が、今も必要か（テスト担当向け）。
- 未コミットの作業中の変更の評価（README.md、.claude/commands/expand.md、word-expansion-research/SKILL.md、未追跡の reading_length.rb）。reading_length.rb が RuboCop の対象になるかも未確認。
- credentials の `admin:` キー（読まない指示のため）。

### Critical Files for Implementation
- lib/tasks/backfill.rake
- CLAUDE.md
- docs/overview.md
- docs/data-model.md
- config/deploy.rb

## 棚卸し（21483dd）

- 前提: `git diff a04f375..21483dd -- app config lib db test script tools` は空。行番号はそのまま使える。
  変わったのは、この記録が「未コミットの作業中の変更」として評価を見送った 4 ファイル（README.md・.claude/commands/expand.md・word-expansion-research の SKILL.md と reading_length.rb）だけ。いずれもコミット済みになった（83e36d2・f7b88da）。中身の評価は B-07 に任せる。
- **陳腐化: 0 件。**
- **重複**（計画書 §9 で同じ改修項目に束ねてある）:
  - CFG-01・CFG-05 ↔ DOC-01（デプロイの実態。D1-01）
  - CFG-02 ↔ M-01・M-02・DOC-05・T-06（派生値と backfill。C3-12・D1-04）
  - CFG-03・CFG-04 ↔ M-07・DOC-04（照合順序。D1-03）
  - CFG-09 ↔ DOC-02（合格判定コマンド。D1-02）
  - CFG-10 ↔ J-01（importmap のコメント。D1-15）
- **要確認**:
  - CFG-04: MySQL の挙動は計画書 §1 の実測でおおむね決着済み。残りは T0-06 の特性テストで固める。
  - CFG-15（puma.rb の分岐に効果が無い）: Puma の仕様からの推測で、起動しての確認はしていない。分岐の削除は §7.2 に回してあるが、**D1-17 でコメントを書くときに、書く内容をこの推測に頼らない**こと（確かめられない事実はコメントに書かない）。
  - CFG-09 の db:prepare の動き・CFG-14 の `/cable`・CFG-18 のゼロからの db:migrate: どれも、文書やコメントに書く前に実行して確かめる。手順は P-01 で該当項目に「要確認」として付ける。
- **未確認の範囲のうち、この棚卸しで決着したもの**:
  - GitHub のブランチ保護: `gh api repos/.../branches/main/protection` は「Branch not protected」（404）。**main への直接 push は止められていない**ので、CFG-01 の結論（merge や push がそのまま本番デプロイになる）は強まる。
  - `tools/claude-ai-skill/build.sh:35-37` と `word-reannotation-research/SKILL.md` の description の違い: 一致していないが、意図的なもの。build.sh は「バンドル用のフロントマター＋運用の上書き」を書き出しており、バンドル版は一括の調査（「アノテーションを調べて」）も受けるように広げてある。指摘にはしない。
  - reading_length.rb が RuboCop の対象か: `bundle exec rubocop --list-target-files` に `.claude/` 配下は 1 本も無い。**対象外**。
  - 本番に MeCab が無いこと（CFG-17）: オーナーの運用記録で「本番・CI に MeCab は未導入」と確認できる。
  - B-01 から預かった A-03（seed まわりの精読）: CFG-05・CFG-06・CFG-07 が seed_catalog（RENAMES・品詞名・語種名）、dev_samples.rake（:9・:60・:94）、db/seeds.rb（:31・:35）を読んで指摘している。**A-03 は見送る**。
- **ほかの単位に任せるもの**: indexing_switch_test の中身、User-Agent の切り詰めのテストの有無、system テストの Google Fonts 遮断は B-06。annotation-guidelines とマスタの突き合わせは B-08。
- **見送るもの**:
  - 本番の実際の値（WEB_CONCURRENCY など）: リポジトリの外にあるので、この改修では扱わない。
  - `script/og_default.py` の RING 座標と KanaRing.path の一致: 既定の og:image の見た目の問題で、目的の外にある。
  - research/README.md と .gitignore の細かな対応: 効果が小さい。
  - credentials の `admin:` キー: 読まない。
