> フェーズ1の監査報告（担当: app/models・app/services・app/jobs）。行番号は `a04f375` 時点のもので、**現行の仕様ではない**。
> 統合と採否は [`../ai-legibility-plan.md`](../ai-legibility-plan.md) を参照。

# 監査報告（フェーズ1）担当: app/models（concerns 含む）・app/services・app/jobs　ID: M-

作業は読み取りだけで行った（ファイルの変更なし。テスト・DB・rake は実行していない）。所有者の未コミットの変更（README.md、.claude/commands/expand.md、.claude/skills/word-expansion-research/ 配下）には触れていない。引用した .claude/skills/word-annotation-research/SKILL.md はコミット済みのファイル。

---

## 0. 派生カラム → 算出箇所 → 手段 の一覧表（db/schema.rb と照合）

| 派生カラム | 正の算出箇所 | 手段 | 同じ値を別の場所でも計算している箇所 | backfill の検査 / 修復 |
|---|---|---|---|---|
| word_senses.reading_length | db/schema.rb:168 `char_length(reading)` | STORED | bulk_word_registration.rb:44 `reading.length < MIN_READING_LENGTH`、word_share_card.rb:71 `@sense.reading_length \|\| reading.length`、views/admin/words/duplicates.html.erb:38 `entry.reading.length`、views/admin/word_requests/index.html.erb:60（WordRequestItem には列が無い）、JS reading_counter_controller.js:15（画面用。必要な再計算） | 不要 |
| word_senses.first_char | schema.rb:161 `left(reading,1)`（as_ci） | STORED | site_statistics.rb:387 でキーをカタカナへ畳み直す | 不要 |
| words.surface_length | schema.rb:208 | STORED | — | 不要 |
| words.reading_density | schema.rb:205 `max_reading_length / nullif(char_length(surface),0)` | STORED だが、after_commit で焼き直す max_reading_length に依存（M-02） | — | sense_metrics が必要。docs はこれに触れていない |
| words.char_type_pattern | word.rb:65（before_validation）→ :76 `CharTypePattern.call(surface)` | 値オブジェクト＋before_validation | site_statistics.rb:106-107 が記号を文字列で直書き（`"^ア+$"` `"%漢%"`） | 検査はある（backfill.rake:36-42）。修復タスクは無い（保存し直す） |
| word_senses.rhythm_pattern / vowel_pattern / mora_count / last_char | word_sense.rb:139 → :149 / :150 / :151 / :155 | 値オブジェクト＋before_validation | backfill.rake:11-16 と :45-50 に組み立てが2回複製されている。site_statistics.rb:344（頭子音。first_char から算出） | 検査も修復もある |
| word_senses.ring_crossing_count | word_sense.rb:153 `KanaRing.crossing_count(reading)` | 値オブジェクト＋before_validation | views/words/_kana_ring.html.erb:3・home/index.html.erb:148 が描画のたびに再計算。db/migrate/20260721103000 でも算出（適用済み） | **検査も修復も無い**（M-01） |
| words.sense_count / variant_count / feature_count / min・max_reading_length / max_mora_count / max_small_kana_count / max_chouon_count / max_dakuten_count / min・max_ring_crossing_count / min_reading / max_reading / min_reversed_reading | word_sense_metrics.rb:35-97（UPDATE 1文）。refreshes_word_metrics.rb:16 の after_commit から呼ぶ（WordSense・WordSenseFeature・WordSenseVariant） | after_commit で焼き直す代表値 | test_helper.rb:18（フィクスチャ用に全件焼き直し） | 修復はある（backfill.rake:24-28）。**検査は無い** |
| word_sense_features.target_start | word_sense_feature.rb:14, 31-33（未指定のときだけ最初の出現位置で補完） | before_validation | — | — |
| word_candidates.original_surface / status_changed_at、word_request_items.handled_at | word_candidate.rb:128、:66 / word_request_item.rb:21 | before_validation / before_save | — | — |
| words.updated_at | word_sense.rb:8 `touch: true` | touch | タグ統合の update_all では動かない（M-08） | — |

---

## 指摘（重要度の高い順）

### [M-01] backfill:verify と reading_metrics が ring_crossing_count と代表値を扱わず、CLAUDE.md・data-model の記述と食い違う
- 観点: A・D ／ 確度: 確認済み（親が確認した事実とも一致）
- 根拠:
  - word_sense.rb:148-156 は5つの値を算出する（:153 `self.ring_crossing_count = KanaRing.crossing_count(reading)`）。
  - backfill.rake:10-17 と :44-51 は4つだけ（rhythm / vowel / mora / last_char）。
  - CLAUDE.md:40-41「`backfill:verify` で差分を検出し `backfill:reading_metrics` / `backfill:sense_metrics` で直す」。
  - data-model.md:104「§3.2・§3.3 の値が古いまま残る」、:107 は verify を「差分の検出」と説明している。しかし verify は §3.3（words の代表値）を一切見ていない。
- 問題: 生 SQL で読みを直したあと、手順どおり verify を流しても「不整合はありません」と出る。ring_crossing_count（と、それを集計した words.min/max_ring_crossing_count）は古いまま残り、気づけない。さらに「読みから派生値を組み立てる」処理が3か所にあるため、値オブジェクトを1つ足すと rake 側を直し忘れる。
- 提案: 公開クラスメソッド `WordSense.reading_derivations(reading)`（5つの値を Hash で返す）を正典にし、before_validation・reading_metrics・verify の3か所から使う。verify には ring_crossing_count を加える。代表値は SENSE_METRICS_SQL 等で words の現在値と突き合わせて検査するか、「代表値は検査しない。修復時は sense_metrics を必ず流す」と docs を直す。
- 影響ファイル: app/models/word_sense.rb、lib/tasks/backfill.rake、test/tasks/backfill_task_test.rb、CLAUDE.md、docs/data-model.md
- リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 既存は test/tasks/backfill_task_test.rb:12-48（last_char と char_type_pattern だけを固定）。「ring_crossing_count を update_columns で壊すと verify が報告し、reading_metrics が直す」テストを追加する。フィクスチャの ring_crossing_count は手計算で KanaRing と一致することを確かめた（murder=3、curry=0、pending=12、pending2=3）ので、既存の「不整合なし」テストは壊れない。

### [M-02] reading_density は「DB が保証する」STORED 列として説明されているが、実際は after_commit の値に依存する
- 観点: A・D ／ 確度: 確認済み
- 根拠:
  - schema.rb:205 `as: "(`max_reading_length` / nullif(char_length(`surface`),0))"`
  - data-model.md:69「DB が値を保証するので、直接 UPDATE しても狂わない」
  - CLAUDE.md:31-32 も STORED 列に分類している
- 問題: 読みを直接 UPDATE したとき、sense_metrics を流すまで reading_density は古いまま。「STORED だから安全」と読んだエージェントは修復を省く。
- 提案: data-model §3.1 の表とCLAUDE.md に「max_reading_length（§3.3）経由なので sense_metrics が必要」と注記する（スキーマは変えない）。
- 影響ファイル: docs/data-model.md、CLAUDE.md ／ リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 「読みを変えて保存すると reading_density が追従する」（word_sense_metrics_test に同等のテストがあるかは未確認）

### [M-03] 置き場所の基準がどこにも書かれておらず、overview.md §6 の地図と実ファイル・クラス冒頭の自己申告が食い違う
- 観点: A ／ 確度: 確認済み
- 実態から帰納した基準:
  - app/services は外部プロセスを起動するクラスだけ。app/models には Open3 / system / Process.spawn が0件。
  - app/models は ActiveRecord と、それ以外の Ruby すべて。
  - concerns は複数モデルが include する振る舞い。
  - app/jobs は雛形の application_job.rb だけで、ジョブは0本（perform_later も0件）。
- 地図に無いファイル（overview.md:118-139）:
  - bulk_word_registration.rb（一括登録の本体）
  - word_batch.rb、word_window.rb
  - concerns/refreshes_word_metrics.rb、concerns/tag_master.rb
  - app/jobs
- 分類違い:
  - morpheme_cloud: 地図は「クエリ/集計」。冒頭 morpheme_cloud.rb:1 は「値オブジェクト」で、実体は純粋な計算。
  - word_ranking: 地図・冒頭 word_ranking.rb:1 とも「値オブジェクト」。実体は :59 の Rails.cache＋DB クエリ。
  - word_sense_metrics: 地図は「クエリ/集計」。実体は :105 で UPDATE を実行する書き込み処理。
  - levenshtein: 冒頭 levenshtein.rb:1 は「値オブジェクト」。実体は module_function の関数群。
  - search_regexp: 「値オブジェクト」だが :51-52 で SQL を発行し、Rails.cache も使う。
  - 地図にあって実在しないファイルは無い（全名を照合済み）。
- 問題: 新しいクラスをどこに置き、どの手本に倣うかが一意に決まらない。
- 提案: §6 に上の基準を1行で書く。地図に欠けた項目を足す。分類の語彙を5つに揃える:
  - 値オブジェクト（DB に触れない）
  - クエリ/集計（読み取りとキャッシュ）
  - 書き込み処理
  - フォーム
  - 調査 JSON の入出力
  
  クラス冒頭の種別ラベルも同じ語彙にする。ファイルの移動（サブディレクトリ化）は定数名が変わるので行わない。Zeitwerk の collapse を使う案は計画書への提案のみ。
- 影響ファイル: docs/overview.md と各クラス冒頭のコメント ／ リスク: 低 ／ 外部振る舞いへの影響: なし ／ 特性テスト: 不要

### [M-04] 「かなの畳み込み」が8通りあり、範囲・変換の向き・NFKC の有無がばらばら
- 観点: B ／ 確度: 確認済み
- 根拠:
  - ひらがな→カタカナ（NFKC あり）: word_request_duplicate_check.rb:62-63 `unicode_normalize(:nfkc).tr("ぁ-ゖ", "ァ-ヶ")`、kana_row.rb:74-75（private）、site_statistics.rb:387（インライン）
  - NFKC なし: search_regexp.rb:11-12, 24、helpers/words_helper.rb:148-154（＋downcase）
  - 範囲が違う: reading_extractor.rb:82 `tr("ぁ-んゔ", "ァ-ンヴ")`（ゕ・ゖ は変換せず落とす）
  - 逆向き（カタカナ→ひらがな）: rhythm_pattern.rb:110-113 と mora_count.rb:20-22 の同一コピー
  - 別機能からの借用: word_candidate_duplicate_check.rb:21 が `WordRequestDuplicateCheck.fold` を使う
- 問題: どれを使えばよいか決まらない。依存の向きも不自然（候補の重複チェックが、公開リクエスト用のクラスに依存している）。
- 提案: `KanaFold`（module_function。`to_katakana(text, nfkc: true)` と `to_hiragana`）を正典にし、上の全箇所から呼ぶ。範囲は "ぁ-ゖ" / "ァ-ヶ" に統一する。ReadingExtractor の範囲を変えるのは振る舞いの変更なので、現行の範囲を明示して残す選択肢も計画書に書く。
- 影響ファイル: 上記の各ファイル（新規 kana_fold.rb）
- リスク: 中（RhythmPattern / MoraCount は保存済みの派生値に影響しうる） ／ 外部振る舞いへの影響: 同値に置き換える限りなし
- 先に必要な特性テスト: 既存の rhythm_pattern_test・mora_count_test・kana_row_test・word_request_duplicate_check_test・word_candidate_duplicate_check_test。加えて、半角カナ・合成濁点・ゔ・ゕゖ を含む入力について、各呼び出し元の現在の出力を固定する。

### [M-05] 提案 payload のキー一覧が3か所で食い違い、トップレベルの linguistic_features が黙って捨てられる
- 観点: B・A ／ 確度: 確認済み
- 根拠:
  - annotation_proposal_import.rb:10-11 `PAYLOAD_KEYS`（linguistic_features が無い）
  - annotation_proposal.rb:128-131 `legacy_sense_hash`（無い）
  - reannotation_export.rb:15-16 `SENSE_KEYS`（ある）
  - 捨てる理由はスキル側 SKILL.md:145-147「取り込み側がトップレベルの `linguistic_features` を保持しない」にしか書かれていない
- 問題: コードだけを読むと、トップレベルの特徴が存在しうると誤解する。キーを1つ足すたびに3か所を直す必要がある。
- 提案: AnnotationProposal に SENSE_KEYS・META_KEYS・PAYLOAD_KEYS を単一の正として置き、3か所から参照する。「トップレベルの特徴は保持しない」をコメントで表明する（保持する方針へ変えるのは計画書への提案のみ）。
- 影響ファイル: annotation_proposal.rb、annotation_proposal_import.rb、reannotation_export.rb ／ リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 既存は annotation_proposal_import_test・reannotation_export_test。「トップレベルの linguistic_features は捨てる」を追加で固定する。

### [M-06] 重複チェックが3クラスで別々に実装され、うち1つは冒頭コメントが古い
- 観点: A・B ／ 確度: 確認済み
- 根拠:
  - word_request_duplicate_check.rb:9「Levenshtein.far_apart? の枝刈りで」→ 実装は :113 の `similarity_at_least_chars` だけ。far_apart? の呼び出しはコミット df197ff で削除済み。
  - 3実装の違い:

    | クラス | 比較方法 | 読みの正規化 | 比較対象 | Match の中身 |
    |---|---|---|---|---|
    | bulk_word_registration.rb:183-219 | Levenshtein | なし | 全語 | surface・reading・similarity |
    | word_request_duplicate_check.rb:45-63 | Levenshtein | NFKC＋かなの畳み込み | 公開語だけ（キャッシュ） | word_id を含む |
    | word_candidate_duplicate_check.rb:14-21 | 畳み込んだキーの完全一致 | 記号を除去 | 候補を含む | kind を持つ |
- 問題: 「重複チェックを直して」と言われたとき、どれが正でなぜ違うのかがコードから読めない。一括登録だけは、ひらがなの読みを貼ると判定が変わる。
- 提案: 各クラスの冒頭に、違いが意図であること（対象・比較方法・正規化）を1行ずつ書く。:9 のコメントを現在の実装に合わせる。一括登録に畳み込みを入れるのは振る舞いの変更なので計画書への提案のみ。
- 影響ファイル: 上記3ファイル ／ リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 既存の3テストで足りる。

### [M-07] 照合順序についての説明がコメント・docs どうしで矛盾している
- 観点: A ／ 確度: 文書どうしの矛盾は確認済み。MySQL の実際の挙動は推測
- 根拠:
  - word_sense_metrics.rb:33-34「as_ci のままだと小書き⇔並字・清濁が畳まれて」、data-model.md:146-147 も同じ趣旨
  - 反対の記述: data-model.md:160「`as_ci` なら清濁を区別しつつ」、shiritori_words.rb:5-9「清濁は as_ci でも区別される」
- 問題: どちらを信じるかで、しりとり・索引・カウントの修正方針が逆になる。
- 提案: 理由を「REPLACE / REGEXP_REPLACE をバイナリ比較に固定し、照合順序の同一視に左右されないようにする」に書き換え、清濁の記述を消す。書き換える前に、実際の MySQL での挙動を親が確かめる。
- 影響ファイル: word_sense_metrics.rb、docs/data-model.md ／ リスク: 低 ／ 外部振る舞いへの影響: なし

### [M-08] コールバックを通らない更新経路が、コード上に表明されていない
- 観点: E ／ 確度: 経路は確認済み。影響の一部は推測
- 根拠:
  - タグ統合: genre.rb:67、entity_type.rb:14、part_of_speech.rb:15 の `update_all(...)`
  - app/controllers/admin/annotations_controller.rb:71 `update_all(features_reviewed_at: ...)`（他領域）
  - backfill.rake:12 の update_columns
  - word_sense_metrics.rb:75「updated_at は意図的に更新しない」（ここだけは表明がある）
- 問題: word_sense.rb:8 の touch と、「words.updated_at で鮮度を見る」前提（word_request_duplicate_check.rb:53-57 のコメント、PublishedWordsDigest）は、タグ統合では成り立たない。その結果、sitemap の lastmod や llms-full.txt が最長1日古くなりうる（TTL で救われる）。詳細ページは word.rb:54-60 の cache_dependencies で救われる。代表値に関わる列は update_all していない。いずれもコードからは読み取れない。
- 提案: 各 update_all の直前に「touch と after_commit を通らない。影響と、それを許容する理由」を1行書く。annotations_controller の update_all はモデルのメソッドへ移す（他領域）。
- 影響ファイル: genre.rb、entity_type.rb、part_of_speech.rb ／ リスク: 低 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 不要（コメントのみ）

### [M-09] 詳細ページの ETag が、別表記や特徴の該当部分だけの変更を拾わないおそれ
- 観点: E ／ 確度: 推測（Rails の belongs_to touch は、自身に保存された変更があるときだけ発火する、という仕様に依拠）
- 根拠:
  - word.rb:49-60 の cache_dependencies は別表記も特徴の行も含まない（含むのは linguistic_feature のマスタだけ）
  - word_sense_variant.rb:8 / word_sense_feature.rb:10 の `belongs_to :word_sense` には touch が無い
  - admin/annotations_controller.rb:42-44 は mark_annotated のあと save するだけ
- 問題: 別表記だけを足したり、特徴の target だけを直したりすると、word.updated_at が動かない。すると ETag も変わらず、304 で古い内容が返りうる。
- 提案: まず特性テストで再現を確かめる。再現したら cache_dependencies に別表記と特徴の行を加えるか、両モデルに `touch: true` を付ける（HTML は変わらない）。
- 影響ファイル: word.rb または word_sense_variant.rb・word_sense_feature.rb ／ リスク: 中 ／ 外部振る舞いへの影響: ETag の値が正しく変わるだけ
- 先に必要な特性テスト: 「公開語に別表記だけを足して保存すると、GET /words/:id の ETag が変わる」

### [M-10] 収録基準と立項スコアのしきい値があちこちに散っている
- 観点: B・D ／ 確度: 確認済み
- 根拠:
  - 収録基準: word_sense.rb:33 `MIN_READING_LENGTH = 10` が正。bulk_word_registration.rb:29 に別名の定数があり、views/admin/words/duplicates.html.erb:38 はこの別名を、helpers/word_requests_helper.rb:5 は正の方を参照している。
  - config/locales/ja.yml:191, 291, 409, 848, 1291, 1310 に「10文字」の直書き。848 は、同じ画面で定数による補間と並んでいる。
  - 類似度: bulk_word_registration.rb:26 に SIMILARITY_THRESHOLD の別名。
  - 立項スコア: annotation_proposal.rb:18（SQL の `<= 3`）と :114（`<= 3`）、bulk_proposal_approval.rb:16（`>= 4`。同じ境界の裏返し）。
  - スコアの範囲 1..5: annotation_proposal.rb:106、word_candidate.rb:62、word_candidate_notation_import.rb:89。
- 提案: 別名の定数をやめ、概念の持ち主を直接参照する。ja.yml は `%{min}` で補間する（文言は同じまま）。AnnotationProposal に `ENTRY_CONCERN_MAX = 3` と `ENTRY_SCORE_RANGE = 1..5` を置き、上の各所から参照する。
- 影響ファイル: 上記 ／ リスク: 低 ／ 外部振る舞いへの影響: なし（文言は同一に保つ）
- 先に必要な特性テスト: 既存の system/word_request_form_test（min の補間）、annotation_proposal_test、bulk_proposal_approval_test

### [M-11] 「代表語義」の選び方が2通りある
- 観点: B・E ／ 確度: 確認済み（両者が食い違う場面が起きるかは推測）
- 根拠:
  - `min_by(&:id)`: related_words.rb:19、shiritori_words.rb:21、word_share_card.rb:61
  - `.first`: proposal_application.rb:19、bulk_annotation.rb:47、views の home/index.html.erb:77・words/show.html.erb:66・words/_entry_row.html.erb:7
  - word.rb:3 の has_many には order が無い
- 問題: 同じページで、円環は `.first`、関連語・しりとり・共有カードは最小 id を起点にしうる。`.first` は preload が返した順（暗黙に主キー順）に依存している。
- 提案: 正典を `Word#primary_sense`（`word_senses.min_by(&:id)`）にし、全箇所をこれに置き換える。
- 影響ファイル: 上記 ／ リスク: 低 ／ 外部振る舞いへの影響: 現状の順序が一致している限りなし
- 先に必要な特性テスト: 複数語義の語で、詳細ページの円環としりとりの起点が同じ語義になることを固定する。

### [M-12] 調査 JSON の読み方が3通りある
- 観点: B ／ 確度: 確認済み
- 根拠:
  - 正典 research_json.rb:3-17 を使うのは word_candidate_expansion_import.rb:20 と notation import。
  - bulk_word_registration.rb:253-262 はフェンスを剥がしたあと独自に JSON.parse している（array_at と同じ処理）。
  - annotation_proposal_import.rb:41 は素の `JSON.parse(@json_text)` で、```json フェンス付きの JSON を貼ると失敗する。
  - 入口のメソッド名も import（:18）と call で揃っていない。
- 提案: すべて `ResearchJson.array_at` に統一し、入口は `call` に揃える。AnnotationProposalImport がフェンス付きを受け付けるようになるのは受理範囲の拡大なので、計画書で明記する。
- 影響ファイル: bulk_word_registration.rb、annotation_proposal_import.rb ／ リスク: 低 ／ 外部振る舞いへの影響: 管理画面のみ
- 先に必要な特性テスト: annotation_proposal_import_test にフェンス付き入力の扱いを追加して固定する。

### [M-13] 「1行ずつ独立に取り込む」処理のトランザクションの張り方が4通りある
- 観点: B・E ／ 確度: 確認済み
- 根拠:
  - 行ごとにトランザクション: bulk_word_registration.rb:168（`ActiveRecord::Base.transaction`）
  - トランザクション無し: word_candidate_intake.rb:44。しかも :35 のコメントは「BulkWordRegistration と同じ作法」と書いており、実装と合っていない。
  - 外側のトランザクション内で RecordNotUnique を rescue して続行し、savepoint は張らない: word_candidate_expansion_import.rb:24 と :53。MySQL が文単位で巻き戻すことに暗黙に依存している。
  - 外側＋行ごとの savepoint: word_candidate_notation_import.rb:28 と :47-54（`requires_new: true`）。理由もコメントで表明している。
  - トランザクションの受け手も ActiveRecord::Base / モデル名 / インスタンス（genre.rb:62、tag_master.rb:25）が混在している。
- 提案: 正典を NotationImport の方式にし、ExpansionImport をそれに揃える。Intake のコメントを実装に合わせる。受け手は「主に書き込むモデル」.transaction に統一する。
- 影響ファイル: 上記 ／ リスク: 中 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: word_candidate_expansion_import_test に「重複した語の行が、他の行を巻き戻さない」を先に固定する。

### [M-14] 外部コマンドを包む3サービスで、フォールバックの書き方が揃っていない
- 観点: B・E ／ 確度: 確認済み
- 根拠:

  | サービス | 有無判定のキャッシュ | 例外の捕まえ方 | タイムアウト |
  |---|---|---|---|
  | share_card_renderer.rb | :26-30 でクラスに保持し、プロセスごとに1回（コメントで表明あり） | — | :16 TIMEOUT=10 |
  | reading_extractor.rb | :70-74 はインスタンスに保持。:27 の `self.call` が毎回 new するので、実質リクエストごとに `mecab --version` を起動する（表明なし） | :42 `rescue StandardError`（広すぎる） | :36 の Open3.capture2 に無し |
  | morpheme_extractor.rb | :49-53 メモ無し（public） | :45 は Errno・IOError | — |
- 問題: 手本が一意に決まらない。overview.md:184-185 の「判定はプロセスごとに1回」は rsvg-convert だけの話なのに、MeCab もそうだと誤解しやすい。ReadingExtractor は CLAUDE.md の「タイムアウトを必ず入れる」に準拠していない。
- 提案: ShareCardRenderer を正典にし、他の2つも有無判定をクラスで1回だけ行う形に揃える。ReadingExtractor にタイムアウトを入れるのは計画書への提案のみ（コマンドが無いときのフォールバックは維持する）。
- 影響ファイル: app/services の3ファイル ／ リスク: 低〜中 ／ 外部振る舞いへの影響: なし
- 先に必要な特性テスト: 既存の test/services/*（環境によっては skip）。スタブで「コマンドが無ければ全件 nil」を固定するテストを追加する。

### [M-15] 使われていないコード（テスト専用を含む）
- 観点: C ／ 確度: 確認済み
- 検索方法:
  - メソッド名と定数名を `rg -w` で検索した。対象は app・lib・config・db/seeds.rb・test の *.rb *.erb *.rake *.builder。
  - send / public_send で文字列から組み立てた呼び出し（WordRanking の metric_column、WordSenseSearch の SOUND_COUNT_FILTERS）は目視で確認した。
  - i18n キーの組み立てと、case 文での分岐も目視で確認した。
- app でもテストでも参照が無いもの:
  - bulk_word_registration.rb:59-60 の `MergedEntry#match?` と `#differ?`。ビューは admin/words/_reading_status.html.erb:1-8 で `row.status` を case で分岐している。
  - word_candidate.rb:40 の `DECISIONS`。参照はコメント（:89、word_candidate_review.rb:9）だけで、実体は word_candidate_review.rb:10 の CHOICES と :91-98 の case に重複している。
- テストからしか呼ばれないもの:
  - levenshtein.rb:53 `far_apart?`
  - levenshtein.rb:12 `distance`、:41 `similarity`、:100 `distance_within`（levenshtein_test.rb:112-130 で、最適化版と突き合わせる参照実装として使われている）
  - word_request_duplicate_check.rb:19-20 `exact?` / `similar?`。ビュー（word_requests/_row.html.erb:15-16）は `result.kind` を文字列に展開して使う。
  - genre.rb:28-30 `root_genre`
  - kana_ring.rb:49 `visited_chars`
  - word_sort.rb:72 `RANKING_KEYS`
- 到達しない分岐（ビュー層・他領域）: views/words/_kana_ring.html.erb:4-8 の else。`crossing_count` は常に Integer を返す。
- 提案: 未使用のものは削除する。テスト専用のものは「テスト用の参照実装」と明記する。これを削除する場合は既存テストの整理を伴うので、計画書で判断する。
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [M-16] コメント・命名と実装の小さな食い違い（まとめ）
- 観点: A ／ 確度: 確認済み
- word.rb:17「注釈済み(公開されない未完了)」は `unannotated` スコープの説明で、正しくは「未注釈」。
- proposal_application.rb:1 と :17 は「保存しない」と書くが、`persist: true` のときは :50-51 の `word_origin_ids=` が、永続化済みの語義に対して中間表へ即座に書き込む。
- word_candidate_duplicate_check.rb:46 `#register` は照合用のメモリに足すだけで、何も保存しない。`WordCandidate.register_for!` や一括登録の `register` と紛らわしい。
- reannotation_export.rb:74 `annotated?` は「注釈が何か付いているか」の意味で、`Word.annotated`（公開済み）と同名で意味が違う。
- site_statistics.rb:2-3 は rhythm_pattern 列への GROUP BY を謳うが、実際にはこの列を参照していない。
- kana_row.rb:1-3 は用途を統計だけと書いている。実際には KanaRing（kana_ring.rb:85-88）経由で保存列 ring_crossing_count に使われるので、規則を変えると保存済みの派生値に波及することが読めない。
- word_request_item.rb:27-31 は読みの改行を空白に置き換えるが、word_sense.rb:143-145 は読みの改行を除去する。読みの改行処理が2通りある。
- CLAUDE.md:44-48 の as_ci の列挙に word_candidates.surface / original_surface が無い（schema.rb:80, 85 と data-model.md の表にはある）。
- 提案: それぞれ1行ずつ直す。改名は計画書で判断する。 ／ リスク: 低 ／ 外部振る舞いへの影響: なし

### [M-17] 派生値や公開集計を、ビューやコントローラで再計算・二重に集計している
- 観点: D ／ 確度: 確認済み
- 根拠:
  - words/_kana_ring.html.erb:3 は、保存列があるのに円環交差数を再計算している（呼び出し元の words/show.html.erb:202 は reading だけを渡す）。
  - site_statistics.rb:106-107 は CharTypePattern の記号をリテラルで書いている。
  - 「今月の新収録」は site_statistics.rb:119 と home_controller.rb:19 の別実装。コメントでは「同じ定義」と明言している。
  - 公開語数 `Word.annotated.count` は home_controller.rb:13（1時間）、pages_controller.rb:9-11（1日）、site_statistics.rb:47（1日）でそれぞれ別の TTL でキャッシュされる。
- 提案: ビューは保存列を使う（パーシャルに sense を渡す）。SQL パターンは定数から組み立てる。公開件数の集計は1クラスに寄せる。TTL の揃え方は計画書で決める。
- リスク: 低 ／ 外部振る舞いへの影響: 画面ごとの数値の食い違いが解消されうる（計画書で明記）

### [M-18] キャッシュの書き方が3系統あり、無効化はすべて TTL 任せ
- 観点: B・E ／ 確度: 確認済み
- 根拠:
  - 版付き定数＋TTL＋race_condition_ttl: site_statistics.rb:11-15, 34、published_sense_counts.rb:8-12, 27-28
  - race_condition_ttl だけ無い: word_ranking.rb:59（11枠を同時に作る）
  - 内容から作る鍵: word_request_duplicate_check.rb:55-57（呼ぶたびに COUNT と MAX を発行）
  - リテラルの鍵: search_regexp.rb:51
  - プロセス内のメモ（再起動まで保持）: morpheme_cloud.rb:122-128、morpheme_frequencies.rb:33-35、linguistic_feature_glossary.rb:12, 22、share_card_renderer.rb:27
  - `Rails.cache.delete` はアプリ全体で0件
- 提案: 正典を SiteStatistics の形にする。プロセス内メモのクラスには「再起動で読み直す前提」を1行書く。WordRanking に race_condition_ttl を足すのは計画書への提案のみ。
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [M-19] 結果オブジェクトと入口メソッドの形が揃っていない
- 観点: B ／ 確度: 確認済み
- 根拠:
  - 大半は Struct(keyword_init)。Data.define は座標や組版だけ（kana_ring.rb:20、radial_chart.rb:20、share_card_typesetter.rb:18-20、morpheme_cloud.rb:107-113）。
  - 位置引数の Struct が1つだけある（related_words.rb:10）。
  - bulk_word_registration.rb:167-180 は Symbol とエラー文字列を混ぜて返す。
  - 失敗の表し方が nil / フラグ（:97-100）/ 例外（proposed_master_creation.rb:5）の3通り。
  - 「Match」という名前の構造体が3種類ある（bulk_word_registration.rb:48、word_request_duplicate_check.rb:25、word_candidate_duplicate_check.rb:14）。
- 提案: 不変の値は Data.define、集計して増やす結果は Struct(keyword_init)、入口は `call`、「入力を読めない」は nil を返す、という規約にする。
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [M-20] 状態の二重表現と、名前で引くマスタへの依存
- 観点: E ／ 確度: 確認済み
- 根拠:
  - 公開状態を annotated_at と annotation_status の2列で表している（word.rb:11-20, 38-47）。両者が一致するのは mark_* を経由したときだけ。
  - word_sense.rb:37 `JAPANESE_ORIGIN_NAME = "日本語"` は seed_catalog.rb:202 の名前に依存している。/admin/tags で改名すると :130-132 のスコープが黙って0件になる。
  - 提案の名前解決（annotation_proposal.rb:62, 78-86）は、name 列の照合順序 ai_ci（ハ＝バ）に依存している。
- 提案: 上の3点をコメントで表明する。
- リスク: 低 ／ 外部振る舞いへの影響: なし

### [M-21] RefreshesWordMetrics の発火条件が表明されていない
- 観点: E ／ 確度: 確認済み（語義の付け替えが起きるかは推測。現状その経路は見当たらない）
- 根拠:
  - refreshes_word_metrics.rb:16 は `after_commit` に on: 指定が無い。meaning だけの更新でも毎回焼き直しが走り、ネスト保存では同じ語を件数分だけ焼き直す。
  - word_sense.rb:159 は新しい word_id だけを返すので、語義を別の語へ付け替えると元の語の代表値が古いまま残る。
- 提案: concern の冒頭に「全 commit で発火する。冪等である。付け替えは想定外」と明記する。
- リスク: 低 ／ 外部振る舞いへの影響: なし

---

## 1. この領域の正典パターン案
- **派生値の値オブジェクト**:
  - `self.call(input)` の純粋関数にし、DB やキャッシュに触れない。手本は app/models/last_char.rb と char_type_pattern.rb。
  - 保存列に使うものは、冒頭に「保存先の列／規則を変えたら backfill」を書く（今は docs/rhythm_pattern.md:59 にしか無い）。
- **読み由来の派生値の組み立て**:
  - word_sense.rb:148-156 を公開メソッドにし、backfill と共有する（M-01）。
  - 代表値は現行の WordSenseMetrics ＋ RefreshesWordMetrics のまま。
- **クエリ**:
  - scope を積み上げる形。手本は word_sense_search.rb。
  - 画面の区画ごとのクエリは related_words.rb と word_batch.rb。
- **集計＋キャッシュ**:
  - 手本は site_statistics.rb:11-15, 33-35（版付きの CACHE_KEY・CACHE_TTL・RACE_CONDITION_TTL・`self.fetch`）。
- **調査 JSON の取り込み**:
  - 手本は word_candidate_notation_import.rb。
  - ResearchJson.array_at で読み、入口は `call`、形が読めなければ nil を返す。
  - 外側のトランザクション＋行ごとの `requires_new`、結果は Struct(keyword_init)。
- **書き出し**:
  - 手本は annotation_research_export.rb の as_json / to_json（VERSION 付き）。
- **外部コマンド**:
  - 手本は share_card_renderer.rb。
  - 有無判定はクラスで1回、コマンドは配列で渡す、SystemCallError を捕まえる、TIMEOUT を持つ。
- **その他の横断ルール**:
  - かなの畳み込み: 新設の KanaFold を正典にする（M-04）。
  - しきい値: 概念の持ち主に1つだけ置く（M-10）。
  - 状態: 間隔を空けた整数の enum。手本は word_candidate.rb:29-32。
  - 代表語義: `Word#primary_sense` を新設（M-11）。
  - トランザクション: 主に書き込むモデルの `.transaction`。

## 2. コードに表明すべき暗黙の前提の一覧
1. **照合順序**
   - as_ci は、かなの種類と小書きを同一視し、清濁は区別する。shiritori_words.rb には表明があるが、word_sense_metrics.rb と矛盾している（M-07）。
   - 提案マスタの名前解決は、name 列の ai_ci に依存している。
   - REGEXP は、かなを同一視しない（search_regexp.rb には表明あり）。
2. **読みはカタカナという前提**
   - reading_extractor.rb:76-79 と search_regexp.rb が前提にしているが、モデルは強制していない。フィクスチャの読みはひらがな（test/fixtures/word_senses.yml:10）。
   - そのため、ひらがなで保存された読みは正規表現検索に当たらない。
3. **鮮度の判定**
   - touch と words.updated_at に依存している。update_all では成り立たない（M-08）。
   - ETag の対象に別表記が入っていない（M-09）。
4. **after_commit**
   - 発火の回数と条件（M-21）。
   - フィクスチャはコールバックを通らない（test_helper.rb:18、フィクスチャの派生値は手書き）。
5. **ジョブ**
   - ジョブは0本で、:async アダプタも未使用。重い処理はすべてリクエスト内で同期実行している（代表値の UPDATE、MeCab、rsvg-convert、統計の約0.8秒の集計）。
   - CLAUDE.md の「重い処理は ActiveJob で非同期化する」と実態が違う。
6. **キャッシュ**
   - 無効化は TTL だけ。本番は :memory_store でワーカー間で共有されない。
   - プロセス内のメモは再起動するまで有効（M-18）。
7. **外部コマンドの有無判定の粒度**
   - rsvg-convert はプロセスごとに1回、MeCab は呼び出しごと。
   - MeCab の呼び出しにはタイムアウトが無い（M-14）。
8. **MySQL 固有の前提**
   - トランザクション内で RecordNotUnique を rescue して続行する（word_candidate_expansion_import.rb:53）。
   - JSON の `->>`（annotation_proposal.rb:18）。
   - STORED 列が非正規化列に依存している（M-02）。
9. **値オブジェクトの規則変更は保存済みの派生値を古くする**
   - 例: KanaRow → KanaRing → ring_crossing_count。
10. **その他**
    - 代表語義は最小 id（M-11）。
    - 公開状態は2列で表している。
    - 「日本語」という語種名に依存している（M-20）。
    - WordShareCard がビュー層に依存している（word_share_card.rb:74 `ApplicationController.render`）。

## 3. コメントの傾向
- app/models と app/services のコメント行は1,402行。大半は「なぜ」を書いたもので、経緯や計測値まで書かれている。
- 「何をしているか」だけを書いたコメントは推定60〜80か所（全体の約5%）。抜き取りからの推定で、全数は数えていない。scope の1行見出しと、小さな private メソッドに集中している。代表例:
  - word_sense.rb:76「モーラ数の完全一致。」
  - word_sense.rb:109「マスタでの絞り込み。」
  - genre.rb:27「大分類(root)を返す。」
  - bulk_word_registration.rb:158「登録できるエントリがあるか。」
  - bulk_word_registration.rb:288「読みの前処理: 前後空白を除く(空なら nil)。」
  - tag_kind.rb:19「表示順に並べた全種別。」
- より大きな問題は逆側にある。コメントに経緯（Issue 番号・日付・計測値）を書き込むため、実装が変わってもコメントだけが残る。例: word_request_duplicate_check.rb:9 の far_apart?、word_sense_metrics.rb:33-34。「なぜ」は残し、経緯は changelog へ移すのがよい。

---

## 未確認のまま残した範囲
- MySQL の実挙動: as_ci と REPLACE / REGEXP_REPLACE が清濁・小書きをどう扱うか（M-07）。
- Rails の belongs_to touch が、変更が無い保存で発火しないこと。M-09 は実際に再現するかを確かめていない。
- word_sense_metrics_test に reading_density の検証があるか（M-02）。
- seed_catalog.rb の名前リスト部分（41-254行）、lib/tasks/dev_samples.rake、db/seeds.rb は精読していない。コールバックを通らない経路は grep で「無し」を確認しただけ。
- コントローラ側（admin/candidates/* の lists_controller.rb:25 にあるトランザクション、concerns/admin/annotation_queue.rb）の詳細。
- stats_helper.rb（18KB）と JS（feature_range_controller.js の target_start 計算など）で派生値を再計算していないか。grep で当たった箇所しか見ていない。
- MorphemeCloud と ShareCardTypesetter の内部コメントの正確さ（冒頭だけ確認した）。
- 未使用判定は名前の grep に基づく。i18n キーやパーシャル名を文字列から組み立てて、モデルの定数やメソッドを参照している箇所は、網羅的には確認していない。

### 実装で最も重要になるファイル
- app/models/word_sense.rb
- lib/tasks/backfill.rake
- app/models/word_sense_metrics.rb
- app/models/annotation_proposal.rb
- docs/overview.md
