> フェーズ1の監査報告（担当: 案内系の文書）。行番号は `a04f375` 時点のもので、**現行の仕様ではない**。
> 統合と採否は [`../ai-legibility-plan.md`](../ai-legibility-plan.md) を参照。

# 監査報告（担当: AI と開発者が最初に読む案内文書／ID: DOC-）

対象は CLAUDE.md、docs/overview.md・data-model.md・char_type_pattern.md・rhythm_pattern.md・genres.md・launch-checklist.md、research/README.md、README.md（HEAD 版）、コミット済みの .claude/commands と skills、tools/claude-ai-skill です。README.md、expand.md、word-expansion-research には未コミットの変更があるので、HEAD 版で監査しました。未コミット分は末尾の別枠に分けています。

**結論**: 実装と食い違う記述のうち、エージェントが誤った操作をしかねないものが 3 件あります。
1. main へ merge すると本番へ自動デプロイされることが、どの案内文書にも書かれていません。
2. 必須チェックのコマンドが、ローカルで動かない形で 4 か所に書かれています。
3. 調査スキルの「この後の流れ」が、登録予定単語（`/admin/candidates`）を入れる前の手順のまま残っています。

一方、照合した大半の記述は実物と一致していました。一致を確認した主なものは次のとおりです。
- genres.md のジャンル名（大分類 10 件・中分類 151 件）は SeedCatalog と完全一致。
- rhythm_pattern.md・char_type_pattern.md の変換規則。
- 環境変数表の各行と既定値。
- ランキングの 11 種、`/stats` の構成（数字の壁＋8 章）、Atom の 20 件。
- 各スキルの JSON のフィールド名と、画面名の文言（ja.yml）。
- CLAUDE.md デザイン節に出てくるトークン・クラスは、すべて CSS に実在。

---

## 指摘（重要度の高い順）

### [DOC-01] main への merge が即本番デプロイになることが、案内文書に書かれていない
- 観点: A・E ／ 確度: 確認済み（GitHub のブランチ保護の設定は、リポジトリの外なので未確認）
- 根拠:
  - 文書側:
    - CLAUDE.md:20「デプロイ: **Capistrano**（`cap production deploy`）。デプロイ後に `deploy:seed` が自動実行」
    - CLAUDE.md:23「CI: …**PR 作成時** と **main への push 時** に実行」
    - overview.md:41-42、README(HEAD):14「デプロイは Capistrano、CI は GitHub Actions」
    - .claude/commands/cppmtm.md:30-31「CI 通過を確認してから `gh pr merge … --merge`」
  - 実物側:
    - .github/workflows/deploy.yml:3-6 が `on: push: branches: - main`、:35 が `bundle exec cap production deploy`。
    - deploy.yml は ci.yml から独立したワークフローで、`needs:` も `workflow_run` もない。main 上の CI と並走し、CI が落ちてもデプロイは止まらない。
    - ci.yml:4 の `pull_request:` は既定の種類なので、PR ブランチへの push のたびにも走る（「PR 作成時」だけではない）。
    - config/deploy.rb:71 は `after "deploy:migrate", "deploy:seed"`。seed が走るのは「デプロイ後」ではなく、マイグレーションの直後。
- 問題:
  - エージェントは、デプロイを人が手で打つ別の工程だと誤解します。`/cppmtm` の merge がそのまま本番反映になることを意識しないまま merge します。
  - 「main の CI が通ったらデプロイされる」とも誤解しかねません。
- 提案:
  - CLAUDE.md の厳守事項に 1 行足す:「main への merge＝本番自動デプロイ（deploy.yml。CI の成否を待たない）」。
  - デプロイの詳細（Capistrano、linked_files、seed のタイミング、deploy.yml が渡す secret）は overview.md の「運用」章に一本化し、README と CLAUDE.md からはリンクだけにする。
  - cppmtm.md の手順 4 に「merge で即本番デプロイ」と注記する。
  - deploy.yml を CI 通過の後に走らせる変更（`workflow_run` など）は、インフラ変更なので計画書への提案のみ。
- 影響ファイル: CLAUDE.md、docs/overview.md、README.md、.claude/commands/cppmtm.md
- リスク: 高 ／ 外部振る舞いへの影響: なし（文書のみ）

### [DOC-02] 必須チェックのコマンドが、動かない形で 4 か所に書かれている（CLAUDE.md の中でも食い違う）
- 観点: A・B・E ／ 確度: 確認済み（連結形が LoadError になることは親の実行で確認済み。ほかは実物照合）
- 根拠:
  - 動かない連結形 `bin/rails test test:system` が次の 4 か所にある:
    - CLAUDE.md:60
    - overview.md:227
    - README(HEAD):41
    - cppmtm.md:19
  - CLAUDE.md の中の食い違い:
    - CLAUDE.md:212 は「`bin/rails test`（単体）/ `bin/rails test:system`（システム）」と別々に打つ形。
    - CLAUDE.md:53「CI と同じ内容なので、ローカルで通れば CI も通る」とあるが、CI は ci.yml:109 の `bin/rails db:test:prepare test test:system`。先頭が rake タスクなので全体が rake として解釈されて通るだけで、同じコマンドではない。
  - WSL での実行方法の所在:
    - overview.md:230-231「実行方法は `CLAUDE.md` とセッションのメモを参照」とあるが、CLAUDE.md には WSL・`CHROME_BIN`・`LD_LIBRARY_PATH` の記述が 1 つもない。
    - cppmtm.md:21-22 は、リポジトリ外のメモリ `system-tests-wsl-chrome` を参照している。
    - リポジトリ内の手がかりは test/application_system_test_case.rb:11-14（`CHROME_BIN`）だけ。
- 問題:
  - 次のエージェントは合格判定の最初の一手で失敗し、「テストが壊れている」と誤診しかねません。
  - WSL の手順が外部メモにしかないので、再現できません。
- 提案:
  - 合格判定コマンドを CLAUDE.md に単一の出典として置く。動く形（`bin/rails test && bin/rails test:system`、または CI と同じ `bin/rails db:test:prepare test test:system`）にし、ci.yml:109 との対応も書く。
  - WSL で必要な環境変数の名前（`CHROME_BIN`・`LD_LIBRARY_PATH`）を併記する。値は環境に合わせる旨だけ書く。
  - overview §9、README、cppmtm からはリンクだけにする。
- 影響ファイル: CLAUDE.md、docs/overview.md、README.md、.claude/commands/cppmtm.md
- リスク: 高 ／ 外部振る舞いへの影響: なし

### [DOC-03] 調査スキルの「この後の流れ」が旧フローのまま（ID 付きで取り込む現行フローと矛盾）
- 観点: A・C ／ 確度: 確認済み
- 根拠（文書側）:
  - word-harvest-research/SKILL.md:
    - :12-13「そのまま `/notation`…へ流せる」
    - :136-137「上部リストはそのままコピペして `/notation` の入力（`research/inputs/notation.txt`）に使う」
    - :172-173「`research/inputs/notation.txt` に貼って `/notation` へ渡す」
    - :130-131「重複は登録 step3 の重複チェックが弾く」
    - :9「`/expand` が『登録済みの種語から横に広げる』」
  - word-expansion-research/SKILL.md（HEAD）:
    - :12-13「そのまま `/notation`…へ流す」
    - :94「そのままコピペして `/notation` の入力」
    - :78-79「重複は登録 step3…が弾く」
  - word-notation-research/SKILL.md:
    - :106-107「そのままコピペして登録／読み調査の入力に使う」
    - :206-207「そのまま一括登録の入力や…`research/inputs/reading.txt` に渡せる」
  - word-reading-research/SKILL.md:24「`notation.txt` 上部の表記リストをそのまま置いてもよい」
  - docs/annotation-guidelines.md:276「`word-expansion-research` スキルが、登録済みの語を種に」
- 根拠（現行の流れと実物）:
  - research/README.md:52「目視で確認してから仕分けの画面に貼る」、:31-33「語は書き出し時の ID `#123` で引く」
  - word_candidate_export.rb:44 が `"##{candidate.id} #{candidate.surface}"` の形で書き出す。
  - word_candidate_notation_import.rb:37-38 は `find_by(id: entry["id"].to_i)` で語を引き、見つからなければ `skip(:unknown…)` で見送る。ID の無い入力から作った JSON は、取り込んでも全件が見送られる。
  - 重複は、仕分けの時点で先に照合されている（word_candidate_duplicate_check.rb:1-11、word_candidate_expansion_import.rb:45-49）。
  - 拡張の種は、登録済みの語ではなく拡張待ちの候補（word_candidate_export.rb:9 `status: "expanding"`）。
  - 実害が今も出ている: research/harvest-cron.log の末尾（2026-09-27 07:21 の実行）で、スキルがオーナーに「`research/inputs/notation.txt` に貼れば `/notation` に回せます」と案内している。
- 問題:
  - スキルに従うと、ID が落ちます。その結果、取り込みで全件「不明」になるか、登録予定単語のステータス管理を素通りします。
  - どちらの手順が正しいか、エージェントには判断がつきません。
- 提案:
  - 流れ・入出力・画面名の単一の出典は research/README.md とする。
  - 各 SKILL の「この後の流れ」は「research/README.md の手順 N（画面名）へ」の 1 行に置き換える。
  - 「上部リストをそのまま次のスキルの入力に」という記述と、「step3 が弾く」という記述を削る。
  - guidelines の「運用」節も「登録予定単語の拡張待ちを種に」へ直す。
- 影響ファイル: .claude/skills/word-{harvest,expansion,notation,reading}-research/SKILL.md、docs/annotation-guidelines.md
- リスク: 高 ／ 外部振る舞いへの影響: なし

### [DOC-04] CLAUDE.md の as_ci 対象カラムの列挙が schema と合わない（word_candidates が抜けている）
- 観点: A・D ／ 確度: 確認済み
- 根拠:
  - CLAUDE.md:46-48 の列挙は、`words.surface`…`word_request_items.surface` / `reading` で終わっている。
  - 実物は db/schema.rb:80 `original_surface … collation: "utf8mb4_0900_as_ci"`、:85 `surface … as_ci` で、word_candidates も as_ci。
  - data-model.md:170 は `word_candidates | surface / original_surface` を載せており、正しい。
- 問題: CLAUDE.md だけを読んだエージェントは、`word_candidates.surface` を ai_ci と誤認します。重複判定や新カラムの照合順序の手本を取り違えます。
- 提案:
  - CLAUDE.md は規約の 1〜2 行だけにする:「既定は ai_ci、読み・表層形のカラムは as_ci を明示。一覧は data-model.md §6（正は schema.rb）」。
  - 列挙そのものは削除する。
- 影響ファイル: CLAUDE.md
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [DOC-05] 派生値の直し方の説明が実装と食い違う
- 観点: A・D ／ 確度: 確認済み
- 根拠（文書側）:
  - CLAUDE.md:40-41「`backfill:verify` で差分を検出し `backfill:reading_metrics` / `backfill:sense_metrics` で直す」
  - data-model.md:108「`backfill:reading_metrics` # 読み由来の派生値を再生成」
  - `ring_crossing_count` は Ruby 側で作る派生値として、CLAUDE.md:33-34 と data-model.md:88 に列挙されている。
  - data-model.md:69「DB が値を保証するので、直接 UPDATE しても狂わない」
- 根拠（実物）:
  - lib/tasks/backfill.rake:7 と :12-17 の再生成対象は rhythm_pattern / vowel_pattern / mora_count / last_char だけで、`ring_crossing_count` を再生成しない。
  - :31-58 の verify も `ring_crossing_count` と words の代表値（min_* / max_*）を検査しない。
  - reading_metrics は `update_columns` なので after_commit が走らず、words の代表値は古いまま残る。
  - char_type_pattern を一括で直すタスクは無い（:63-64「該当 Word の保存で」）。
  - schema.rb:205 の `reading_density` は `max_reading_length / nullif(char_length(surface),0)`。`max_reading_length` は after_commit で焼き直す値（word_sense_metrics.rb:86）なので、読みを直接 UPDATE すると `reading_density` も狂う。
- 問題: 「verify で差分なし＝整合」と誤認されます。KanaRing の規則を変えた後の焼き直し手段もありません。
- 提案:
  - 単一の出典は data-model.md §3 の表とする。列は「カラム／生成箇所／再生成タスク／verify の対象か／依存する派生値」。
  - CLAUDE.md はその表へのリンクと「派生値は手入力させない」だけにする。
  - backfill に ring_crossing_count と代表値の検査を足すのは、コード変更なので計画書への提案。
- 影響ファイル: CLAUDE.md、docs/data-model.md、（提案）lib/tasks/backfill.rake
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [DOC-06] genres.md が書く小分類の追加経路が誤り／「正」がどちらかの主張が循環している
- 観点: A ／ 確度: 確認済み
- 根拠:
  - 追加経路:
    - genres.md:13-14「管理画面（`/admin/annotations` のジャンルピッカー、`/admin/tags/genres`）から随時追加する」
    - 実物の app/models/tag_kind.rb:40-45 は `creatable?` が `key == "linguistic_features"` で、ジャンルは「タグ管理では追加を受け付けない」。
    - 実際の追加経路は 3 つ: `_sense_fields.html.erb`:80-81 のピッカー、`admin/words/_bulk_annotation.html.erb`:17-18、`proposed_master_creation.rb`:46。
  - 循環:
    - seed_catalog.rb:15「出典: docs/genres.md」
    - genres.md:3-4「正（単一の情報源）はコード側」
  - 名前の一覧自体は、SeedCatalog との diff が空（一致）。
- 問題: エージェントがタグ管理にジャンル追加を実装し直すか、genres.md を先に直して SeedCatalog を追従させる、という逆向きの変更をしかねません。
- 提案:
  - genres.md の追加経路を実態に合わせる。
  - SeedCatalog のコメントを「docs/genres.md はこの定数の写し」に直す。
  - genres.md は Issue 85（issues.md:488 確定事項 35「rake で生成し CI で差分検出」）で生成物にするまで、手作業の写しと明記する。
- 影響ファイル: docs/genres.md、app/models/seed_catalog.rb（コメントのみ）
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [DOC-07] overview.md §6「コードの地図」の欠落と、配置の規約が書かれていないこと
- 観点: A・C・D ／ 確度: 確認済み（`git ls-files` と全件照合）
- 根拠:
  - models の欠落: overview.md:121-138 に次が無い。
    - `bulk_word_registration`（一括登録の本体）
    - `word_batch`、`word_window`
    - `concerns/refreshes_word_metrics`、`concerns/tag_master`
  - controllers の欠落:
    - :140-141 に `words/share_cards`・`sessions`・`admin/candidates/*`（5 本）・`admin/word_candidates` が無い。
    - app/controllers/concerns も無い。特に `admin/annotation_queue.rb` は、CLAUDE.md:103 が手本に挙げる `Admin::AnnotationQueue` の所在なのに地図に載っていない。
  - app/helpers（12 本）と test/ の構成（services・helpers・tasks を含む）は、地図に無い。CLAUDE.md:204 も models・controllers・integration・system の 4 つしか挙げていない。
  - CSS: overview.md:39 と :143、CLAUDE.md:176 に `candidates.css` が無い。実物は stylesheets 8 本で、candidates.css を含む。
  - 開発用のダミーデータの仕組みが 2 つある:
    - db/seeds.rb:33-35 は、development では `db/seeds/development.rb` を load する（`db:prepare` で「開発語 NNNN」が入る）。
    - overview.md:145 と :168 は、`db:seed` がマスタを投入することと `dev:sample_data` しか書いていない。
  - 配置の規約が暗黙:
    - app/services は外部コマンドのラッパー 3 本だけ。フォーム・クエリ・取り込みの PORO は app/models に 50 本以上ある。
    - CLAUDE.md:98 は「Service Object… に切り出す」とだけ書き、置き場所を書いていない。
- 問題: 地図に無いものを探して手数が増えます。新しい PORO を app/services に作って、配置が二系統になります。
- 提案:
  - 地図は「ディレクトリ → 役割 → 手本ファイル」の粒度にして CLAUDE.md へ移す。
  - 全ファイルの列挙はやめる（列挙は必ず古くなる）。
  - 「PORO は app/models、app/services は外部コマンドのラッパーだけ」を正典パターンとして明記する。
- 影響ファイル: docs/overview.md、CLAUDE.md
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [DOC-08] 文書に書いた件数とパスが古い
- 観点: A ／ 確度: 確認済み
- 根拠:
  - 検索の条件数:
    - overview.md:83「詳細検索フォーム（13 条件）」と design.md:404「13 の条件」。
    - 実物の app/views/searches/index.html.erb は 14 区画。2026-09-23 の Issue 92（58ff207）で、:60 の濁点・小書き・長音符の区画が加わったため。
  - パス:
    - overview.md:108 の `/admin/annotation_proposals` は、`bin/rails routes` では POST だけ。
    - 実際の画面は `/new`、`/export`、`/export_features`。
- 提案: 件数は文書に書かず、出どころを指す（`WordSenseSearch#to_query_params`、`WordRanking::DEFINITIONS`）。パスは実在する GET を書く。
- 影響ファイル: docs/overview.md、docs/design.md
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [DOC-09] CLAUDE.md の規則が、実在の正典パターンと違う書き方になっている（認証・外部連携）
- 観点: A・B ／ 確度: 確認済み
- 根拠（認証）:
  - CLAUDE.md:78「書き込み系アクションには認証必須の `before_action` を必ず付ける」
  - 実物は application_controller.rb:2 の `include Authentication` と、authentication.rb:5 の全体への `before_action :require_authentication`。認証は全アクションで既定で必須になり、公開側が `allow_unauthenticated_access` で個別に外す（15 か所）。
  - admin/base_controller.rb は中身が空で、:1-3 のコメントが正しい説明をしている。
  - overview.md:54 は「Admin::BaseController 配下は既定で認証必須」とだけ書いており、全体が既定で必須であることが読み取れない。
- 根拠（外部連携）:
  - CLAUDE.md:186-189「重い処理は ActiveJob で非同期化」「ジョブは冪等に」
  - 実物では app/jobs は application_job.rb だけで、`perform_later` / `deliver_later` の呼び出しは 0 件。
  - 実在する重い外部処理 ShareCardRenderer は、意図的に同期処理にしている。タイムアウト（share_card_renderer.rb:16）、Mutex（:22）、プロセスごとの `available?`（:26-30）、ファイルキャッシュで守っている（Issue 89）。
  - CLAUDE.md:190「タイムアウトを必ず入れる」に対し、ReadingExtractor は `Open3.capture2` にタイムアウトが無く（reading_extractor.rb:35）、有無の判定もインスタンス単位（:73-77）。書き方が二系統になっている。
- 問題:
  - エージェントが不要な `before_action` を足したり、`before_action` が無いコントローラを公開と誤読したりします。
  - 共有カードを `:async` ジョブへ移すという「規約どおりの改悪」を招きます。
- 提案:
  - CLAUDE.md の正典パターンに次の 2 つを手本ファイル付きで書く。
    - 認証: 既定で必須、公開だけ `allow_unauthenticated_access`。手本は words_controller.rb:3。
    - 外部コマンド: 配列引数、`available?`、失敗時は nil を返して既定値へフォールバック、タイムアウト。手本は ShareCardRenderer。
  - ActiveJob の節は「現状ジョブは無い。導入するときは相談」に縮める。
  - ReadingExtractor を ShareCardRenderer の書き方に揃えるのは、計画書への提案（MeCab のフォールバックは維持）。
- 影響ファイル: CLAUDE.md、docs/overview.md
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [DOC-10] 調査 JSON の取り込みが 3 通りの書き方になっている／取り込み画面の例文が旧形式
- 観点: B・A ／ 確度: 確認済み
- 根拠:
  - 3 通りの書き方:
    - `ResearchJson.array_at`: word_candidate_expansion_import.rb:20、notation_import.rb:24
    - `JSON.parse(ResearchJson.strip_code_fence(...))` のあと自前で取り出す: bulk_word_registration.rb:256-258
    - フェンスを剥がさない素の `JSON.parse`: annotation_proposal_import.rb:41
  - overview.md:138 は「research_json（調査 JSON の貼り付けを読む）」と、単一の取り込み口のように書いている。
  - 再注釈スキルはチャットに ```json のコードブロックで返す（reannotation SKILL:108-113）が、その貼り先の取り込みだけがフェンスを剥がさない。
  - config/locales/ja.yml:922 の取り込み画面のプレースホルダは、トップレベルに `"meaning"` / `"genre_path"` を置く旧形式。annotation SKILL:145-147 は「旧形式は…使わない」としている。
- 提案:
  - 取り込みの正典を `ResearchJson` に一本化する（コード変更なので計画書への提案。影響は管理画面の中だけ）。
  - プレースホルダを `senses` 形式に直す。
  - 形式の出典は各 SKILL と schema.json とし、取り込みクラスのコメントはそこへのリンクにする。
- 影響ファイル: app/models/annotation_proposal_import.rb、bulk_word_registration.rb、config/locales/ja.yml、docs/overview.md
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [DOC-11] 「言語的特徴だけの再調査データ」の書き出しが、処理するスキルも手順も無い孤立機能になっている
- 観点: C ／ 確度: 確認済み
- 根拠:
  - 機能は実在する:
    - routes.rb:92-94 の `export_features`
    - feature_research_export.rb:31 `"task" => "linguistic_features_only"`（入力は `senses` 配列）
    - 一覧からの導線 admin/words/index.html.erb:72
    - ja.yml:916「Claude Code に貼り付けてください」
  - この入力形式を扱うスキルは無い: annotation SKILL:110-122 は `words`+`masters` だけ、reannotation SKILL:67-68 も同様。research/README にも記載が無い。
  - issues.md:483（確定事項 32）「専用の調査スキルは作らない…書き出しの口は…残る」、:494（確定事項 37）「遡及付与は行わない」。
- 提案: 撤去するか、「使わない（確定事項 37）」と research/README と画面に明記するかを、計画書で判断する（管理画面のみの話）。
- 影響ファイル: research/README.md（または該当コード一式）
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [DOC-12] CLAUDE.md のデザイン節（78 行）が design.md の要約と歴史の混在になっている
- 観点: B・C ／ 確度: 確認済み（参照しているトークン・クラスはすべて実在するので、嘘ではない）
- 根拠: CLAUDE.md:106-183 に日付や経緯が並ぶ。
  - :119「`--font-brand`…2026-09-05 に廃止済み」
  - :128「2026-09-03 に…重ねた」
  - :134「`.image-slot` は 2026-09-09 に partial ごと削除済み」
  - :148「2026-09-03 の計測で…88% が AA 未達」
  - :156「2 通り試して、どちらも不採用」
  - :167「試作の結果不採用。再提案しない」
  - :168-171「白抜き…不採用（2026-09-05 オーナー判断）」
  - :178「（2026-09-06 オーナー指示）」
  - :109 自身が「値と経緯の正は design.md」と書いている。
- 提案:
  - 値と規約は design.md へ集約する。
  - 「再提案しない」系は design.md の「禁止事項」節に一元化する（現行の規約として保つ）。
  - 日付・計測値・試作の経緯は docs/history/ へ移す。
  - CLAUDE.md には「UI を触るなら design.md 必読」と、禁止事項を 5 行程度だけ残す。
- 影響ファイル: CLAUDE.md、docs/design.md
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [DOC-13] コード上に表明されていない暗黙の前提
- 観点: E ／ 確度: 項目ごとに記載
  - INDEXING_ENABLED は「空でない値なら何でも解禁」（確認済み）:
    - config/application.rb:54 は `ENV["INDEXING_ENABLED"].present?` なので、`false` を設定しても解禁になる。overview.md:200 はこの点に触れていない。
    - 同じ箇所の :51-53 のコメント「公開準備中…達したら解禁する」は古い。解禁は 2026-07-19 に済んでいる（launch-checklist.md:3）。
  - /harvest の定期実行の実体がリポジトリの外にある（確認済み）:
    - ローカルの crontab に、`/harvest` をヘッドレスで定期実行する行がある（コマンド行は省略）。
    - research/README.md:55 には時刻しか書かれていない。
    - スキルが Bash を要するように変わると、定期実行が黙って失敗する。
  - claude.ai 用のスキル束は派生物:
    - tools/claude-ai-skill/build.sh:63-75 は、次の 5 つから束を作る: reannotation と annotation の SKILL、guidelines、glossary、schema/example。
    - これらを直したら再生成して再アップロードが要る、という記述がどこにも無い。言及は overview.md:151 の 1 行だけ（確認済み）。
  - 本番に MeCab が無い（推測）:
    - stats.rake:3 は「本番・CI には MeCab が無い」、word_candidate_duplicate_check.rb:3 も同旨。
    - 一方、overview.md:176 と research/README.md:74-75 は、step2 で「MeCab の暫定読みと突き合わせる」前提の書き方。
  - Ruby 側の判定が照合順序に依存している（コード上は確認済み、影響は推測）:
    - word_candidate.rb:70-74 の `register_for!` は `where(surface:)` で引くので、as_ci でかなの種類・大文字小文字が同一視される。
    - word_request_duplicate_check.rb:27 は「照合順序 as_ci と同じ扱いに揃える」と、Ruby 側で照合順序を真似ている。
    - どちらも data-model.md §6 に書かれていない。
- 提案:
  - 各項目を overview.md（運用・環境）と data-model.md §6 に 1 行ずつ足す。
  - cron の定義とスキル束の再生成手順は、research/README.md に書く。
- リスク: 中 ／ 外部振る舞いへの影響: なし

### [DOC-14] 注釈スキルが参照する公開 API のホストが canonical と違う
- 観点: A ／ 確度: 推測（www への到達はネットワークで未確認）
- 根拠:
  - annotation SKILL:27 は `https://www.nagai-kotoba-database.jp/words.json`。
  - config/application.rb:49 の canonical は `https://nagai-kotoba-database.jp`。stats.rake:12 もこちら（www なし）。
  - issues.md:393（Issue 27）「www あり/なし…の正規化も無い」。
- 提案: www なしに統一する。
- 影響ファイル: .claude/skills/word-annotation-research/SKILL.md
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [DOC-15] 完了記録の置き場所が文書どうしで矛盾している
- 観点: A ／ 確度: 確認済み
- 根拠:
  - overview.md:236「その場合も完了記録は `issues.md` に残す」
  - issues.md:487（確定事項 35）「完了アーカイブを changelog.md に分離する（本ファイルは『これからやること』と『確定事項』だけ）」
  - overview.md:13 も「これまでに入れたもの → changelog.md」と書いている。
- 提案: overview.md:236 を changelog.md に直す。
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [DOC-16] 残骸と「もう無いもの」への言及（1 項目にまとめた）
- 観点: C・A ／ 確度: 確認済み
- docs 側:
  - issues.md:492「改善調査〈docs/improvements.md〉」。このファイルは存在せず、`git log --all` にも履歴が無い。
  - .gitignore:40 のコメント「(/notation・/reading・/annotation)」。実際は /expand・/harvest・/reannotation も research/ を使う。
- コメントと名前のずれ:
  - word.rb:17 は `unannotated` スコープを「『注釈済み(公開されない未完了)』の集合」と説明している（名前と逆）。
  - config/deploy.rb:59 の desc「管理者(seed)を作成/更新する」。実際の seed はマスタも投入する（db/seeds.rb:28-31）。
  - bulk_word_registration.rb:5「※将来 LLM 等で読みを強化する差し込み口も」。すでに research_json（:18-20）として実装済み。
- コードの残骸:
  - app/helpers/articles_helper.rb:1-2（空のモジュール）。対応する articles テーブルは作成と削除のマイグレーションだけが残っている（20260629132054 / 20260630152904）。
  - test/application_system_test_case.rb:26-28 が Google Fonts を遮断している。アプリはフォントを読まない（app/ に googleapis が 0 件）。
  - config/locales/en.yml:30-31 は Rails 既定の `hello: "Hello world"` のまま。
  - lib/tasks/dev_samples.rake:9-11 が品詞「名詞」を作る。SeedCatalog::PARTS_OF_SPEECH（seed_catalog.rb:221-225）と、annotation SKILL:23「マスタに『名詞』は無い」に反する（開発環境限定）。
- 提案: 各所を削除または訂正する。コード側の削除は計画書への提案。
- リスク: 低 ／ 外部振る舞いへの影響: なし

---

## 別枠: 未コミットの作業中の変更（所有者の作業中の内容。参考として記載）

- **README.md**:
  - CI/CD の行に「`deploy.yml`: main への push で…本番デプロイ」を追加している。DOC-01 のうち README の分は解消に向かっている。
  - 一方、「ジョブ | ActiveJob（`:async` アダプタ）」は、ジョブが実在しないという DOC-09 の誤解を広げる。
  - 規模の数値（テーブル 16、マイグレーション 29、Stimulus 31、stylesheets 8、helpers 12、docs 13）は、現時点では実物と一致した。ただし DOC-08 と同じく、放っておけば古くなる。
- **expand.md と word-expansion-research/SKILL.md、未追跡の reading_length.rb**:
  - スキルに `bin/rails runner` を持ち込んでいる（アプリと DB の起動が必要になる）。
  - reading_length.rb は `extractor.send(:normalize, …)` で ReadingExtractor の private メソッドに依存している。
  - 読みの表記規則を、guidelines §4 に対してさらに重複させている。
  - 「重複は登録 step3 の重複チェックが弾く」「上部リストはそのまま /notation の入力」という DOC-03 の記述は残ったまま。

---

## 1. 同じ事実が複数の文書に書かれている箇所と、単一の出典案

| 事実 | 記載箇所 | 単一の出典案 |
|---|---|---|
| as_ci 対象カラム | CLAUDE.md:42-48（欠落あり）、data-model.md:153-175、overview.md:37、README（未コミット） | data-model.md §6（カラムの正は schema.rb） |
| 派生値の 3 分類と直し方 | CLAUDE.md:30-41、data-model.md:63-110、overview.md:67-68、char_type_pattern.md:4-5、rhythm_pattern.md:4-5 と :58-59、backfill.rake のコメント | data-model.md §3 の表 |
| 必須チェックのコマンド | CLAUDE.md:55-61 と :212、overview.md:222-228、README(HEAD):36-42、cppmtm.md:14-20、ci.yml:109 | CLAUDE.md の合格判定コマンド節（ci.yml と一致させる） |
| システムテストの WSL での実行 | overview.md:230-231（CLAUDE.md を指すが記載なし）、cppmtm.md:21-22（外部メモ）、application_system_test_case.rb:11-14 | CLAUDE.md の合格判定コマンド節 |
| デプロイと CI | CLAUDE.md:20-23、overview.md:41-42 と :207 と :213-218、README(HEAD):14、deploy.rb、deploy.yml、issues.md:479 | overview.md に「運用」章を新設（CLAUDE.md には厳守事項 1 行） |
| 環境変数 | overview.md:196-218、launch-checklist.md:19-30、config/application.rb のコメント、README:28-32、db/seeds.rb:12-16 | overview.md §8 |
| ブランチ命名と PR の進め方 | overview.md:233-240、cppmtm.md:24-25 | CLAUDE.md の厳守事項 |
| 認証 | CLAUDE.md:14-16 と :77-79、overview.md:47-55、README:8、data-model.md:14 と :53 | 仕組みは overview.md §3、書き方は CLAUDE.md の正典パターン |
| 公開方針・アカウント機能なし | CLAUDE.md:11-13、overview.md:30-31 と :97、README:8 | overview.md §1（CLAUDE.md は厳守事項 1 行） |
| ローカル環境の立ち上げ | overview.md:154-194、README(HEAD):17-32 | overview.md §7 |
| 外部コマンドのフォールバック | CLAUDE.md:191-192、overview.md:172-194、各サービスのコメント | overview.md §7 の表 |
| 収録基準（読み 10 文字） | CLAUDE.md:10、overview.md:24、README:3、guidelines §0、各 SKILL | guidelines §0 と `WordSense::MIN_READING_LENGTH` |
| 読みの表記規則 | guidelines §4、reading SKILL:39-44、未コミットの expansion SKILL | guidelines §4 |
| 立項スコアの定義 | guidelines §2、annotation SKILL:158-164、notation SKILL:72-78、`WordCandidate::DOUBTFUL_ENTRY_SCORE` | guidelines §2 |
| 調査の流れ（パイプライン） | research/README.md:29-85、各 SKILL の「この後の流れ」、guidelines「運用」、word_candidate.rb のヘッダ、routes.rb:71-74 | research/README.md |
| 調査 JSON の形式 | 各 SKILL.md、schema.json、各取り込みクラスのヘッダコメント、ja.yml:922 | 各 SKILL.md と schema.json |
| ジャンル一覧 | genres.md、SeedCatalog::GENRES | SeedCatalog（genres.md は生成物にする。Issue 85） |
| デザイン規約 | CLAUDE.md:106-183、design.md | design.md |
| 画面一覧 | overview.md §5、routes.rb のコメント、research/README、design.md §10 | ルートの正は routes.rb、役割の説明は overview.md §5 |
| 公開ホスト名 | application.rb:49、annotation SKILL:27（www 付き）、stats.rake:12 | `CANONICAL_HOST` |

## 2. CLAUDE.md の再編案（200 行程度、4 区分に限定）

| 現在の節 | 行 | 分類 | 行き先と扱い |
|---|---|---|---|
| 最初に読む | 1-4 | 残す（書き換え） | 地図の入口にする |
| 言語・コミュニケーション | 6-7 | 残す | 厳守事項 |
| 概要・公開方針・アカウントなし | 9-13 | 一部を残す | 「公開面に書き込み経路を増やさない」「アカウント機能を作らない」は厳守事項。概要は overview.md §1 へ |
| 認証 | 14-16 | docs へ移す | overview.md §3。CLAUDE.md には正典パターン（`allow_unauthenticated_access`）だけ |
| バージョン・構成・テスト FW | 17-19 | 削除 | overview.md §2、Gemfile、.ruby-version と重複 |
| デプロイ | 20-22 | docs へ移す | overview.md の「運用」章へ。厳守事項「main への merge＝本番デプロイ」を新設 |
| CI | 23 | 統合 | 合格判定コマンド節へ（ci.yml を指す） |
| データモデル: 関係 | 25-29 | 削除 | data-model.md と重複。地図からリンク |
| 派生値 | 30-41 | 3 行に圧縮して残す | 正典パターン「手入力させない。一覧は data-model.md §3」。:37-39 の last_char の理由は data-model.md §3.2 と重複するので削除 |
| 照合順序 | 42-48 | 規約 2 行だけ残す | 厳守事項。列挙は削除（DOC-04） |
| コミット前に必ず実行 | 52-66 | 残す（直す） | 合格判定コマンド。動く形にし、WSL の環境変数名を書く |
| セキュリティ | 70-84 | 残す | 厳守事項と正典パターン。:78-79 は実態（既定で認証必須）に直す。:76 の手本（WordSort / WordSenseMetrics）は正典パターンへ |
| ActiveRecord / DB | 86-94 | 圧縮して残す | :92-93 は厳守事項。一般論（N+1、インデックス）は 1〜2 行に |
| 設計・アーキテクチャ | 96-104 | 残す（補強） | 正典パターン。:102-104「定義は 1 箇所」が核。配置の規約（PORO は app/models、services は外部コマンドだけ）を追加 |
| デザイン / UI | 106-183 | 大半を docs へ移す | design.md へ。CLAUDE.md には「UI を触るなら design.md 必読」と禁止事項 5 行程度 |
| 重い処理・外部連携 | 185-192 | 残す（直す） | 正典パターン（ShareCardRenderer 型）。ActiveJob の記述は縮める（DOC-09） |
| 可読性・命名 | 194-200 | 一部を残す | :196-198（基準値は概念の持ち主に置く）と i18n は正典パターン。:195 と :199 の一般論は削除 |
| テスト | 202-212 | 圧縮して残す | :205-206（層の使い分け）と :208（キャッシュ検証時の差し替え。手本は test/controllers/searches_controller_test.rb）は正典パターン。:207「2026-09-14 に 1002 本を整理」は docs/history/ へ。:212 は合格判定コマンド節へ統合 |
| やらないこと / 確認すること | 214-221 | 残す | 厳守事項。:221 の事故の回数と経緯は issues.md と changelog.md へのリンクだけ |

**「再提案しない」ための不採用の記録の扱い**
- **現行の規約として残すもの**: 次の 6 つは design.md の「禁止事項」節に一元化し、CLAUDE.md からは 1 行でリンクする。
  - :123-127 過去のデザインの要素を使わない
  - :133-134 `.image-slot` を再導入しない
  - :155-157 本文に面を敷かない
  - :167 縦罫 2 本・ニューモーフィズム・カード風
  - :168-169 標識の白抜き
  - :182-183 `.is-admin *` の全称セレクタ禁止
- **歴史として docs/history/ へ隔離してよいもの**:
  - :119 `--font-brand` の廃止日
  - :128 2026-09-03 の経緯
  - :148 88% の計測値
  - :170-171 白抜きを再検討するときの測り方（規約として残すなら design.md へ）
  - :178 指示の日付
  - :207 テストの整理本数
  - :208 後半の失敗談
  - :221 事故の回数

**新しい CLAUDE.md の 4 区分の中身（目安）**
- **厳守事項**（約 40 行）
  - 日本語で書く。
  - 公開面の書き込み経路は収録リクエストだけ。アカウント機能は作らない。
  - main への merge は即本番デプロイ。
  - 公開 URL とクエリ名を変えない。
  - 適用済みのマイグレーションは書き換えず、スキーマは db/migrate 経由で変える。
  - 照合順序の規約を守る。
  - gem・JS ライブラリを足さない。web フォント・ビルドツール・CSS フレームワークを入れない。
  - robots・canonical・sitemap を変えるときは URL 空間を確認する。
  - インフラ設定は説明してから変える。
- **正典パターン（手本ファイル付き）**（約 70 行）
  - 認証、Strong Parameters（`Admin::AnnotationQueue::WORD_ATTRIBUTES`）
  - 動的 SQL は定数で書く、「同じ規則は 1 箇所」、基準値の置き場所
  - 派生値、外部コマンド、調査 JSON の取り込み（ResearchJson）
  - PORO の配置、テストの層、i18n
- **地図**（約 50 行）: ディレクトリ → 役割 → 手本。docs の索引。
- **合格判定コマンド**（約 20 行）

## 3. docs/ の各文書の分類案

| 文書 | 分類 | 備考（どの節を分けるか） |
|---|---|---|
| overview.md | 現行仕様 | 地図は CLAUDE.md へ移す。「運用」章を新設する |
| data-model.md | 現行仕様 | §5 冒頭「かつて…」（:135-140）は 1 文に圧縮 |
| char_type_pattern.md、rhythm_pattern.md | 現行仕様 | 実装と一致した |
| genres.md | 現行仕様（生成物にする予定） | Issue 85 |
| annotation-guidelines.md | 現行仕様 | 「運用」節は research/README へのリンクにする |
| research/README.md、README.md | 現行仕様 | 流れの単一の出典は research/README.md |
| design.md | 混在 | トークン・コンポーネント規約は現行。日付・不採用・経緯（76 か所）は docs/history/ へ。「禁止事項」節を新設 |
| stats.md | 混在 | §2 紙面構成（確定）は現行。§3 実装フェーズ・§4 追加アイデア・§5 カタログは計画か歴史 |
| issues.md | 混在 | 未完了イシューは現行の計画として残す。確定事項のうち現に効いている規約（28、32、35、37 など）は各文書へ移し、残りは docs/history/ へ |
| launch-checklist.md | 混在 | §4 の継続作業（週次確認）は overview.md の「運用」へ。前提、§1-3、解禁の記録は docs/history/ へ |
| growth-strategy.md | 方針（コード照合は不要） | 「現フェーズの優先順位」は時期に依存するので別扱い |
| changelog.md | 歴史・記録 | docs/history/ へ |
| performance-report.md | 歴史・記録 | 確定事項 35 で「2026-08 の記録として凍結」済み |

---

## 未確認のまま残した範囲（親の裏取り用）
- design.md、stats.md、issues.md、changelog.md、annotation-guidelines.md、growth-strategy.md、performance-report.md の本文と実物の照合。見出しと一部の grep しか見ていない。design.md §3 の「4 箇所」と CSS の一致も未確認。
- .claude/skills/word-annotation-research/schema.json と example.json の中身。AnnotationProposalImport::PAYLOAD_KEYS や ProposalApplication と合っているか（`target_start`・`entry_notes` の扱いなど）。
- `www.nagai-kotoba-database.jp` に到達できるか（DOC-14）。本番に MeCab が無いか、本番の環境変数の値（DOC-13）。
- data-model.md §8「一覧・検索・sitemap・API・統計のすべてがこのスコープを通る」の全経路。
- overview.md §5 の各画面説明の細部（ホーム、/browse、/genres、管理画面の各機能の文言）。
- CharTypePattern の Unicode 境界例（〆、々）。ruby の実行は控えた。
- research/README.md の画面操作の説明（左端をなぞる範囲選択、系統の選択など）と UI 実装の細部。キーの割り当て E/A/H/X は一致を確認した。
- tools/claude-ai-skill の生成物（tmp/ 配下）と、claude.ai にアップロード済みの版が最新か。
- GitHub のブランチ保護の設定（merge 前に CI 必須かどうか）。
