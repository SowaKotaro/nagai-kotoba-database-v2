# リファクタリング台帳

> **進捗の正本はこのファイルだけ**。メモリや会話の記憶よりも、ここに書かれたことを優先する。
> 進め方の決まりは [`STRATEGY.md`](STRATEGY.md)、項目の中身は計画書 [`ai-legibility-plan.md`](ai-legibility-plan.md) にある。
> 再開は `/refactor-resume`。書き換えてよいのはリーダー（メインのセッション）だけ。

## 1. 現在地

<!-- 1 単位を終えるたびに、この表を書き換えて同じコミットに入れる -->

| 項目 | 値 |
|---|---|
| 段階 | 4: 実行 |
| 次の一手 | T0-20（publish_guard と deck が削除済みの語義を数えないことを固定する。system テスト） |
| 次の一手の推奨 effort | high |
| 作業ブランチ | `feature/refactoring` |
| 既存監査の基準コミット | `a04f375`（`audits/` の行番号はこの時点のもの） |
| 台帳を作ったときの main | `e4d2b7a` |

## 2. 段階

| 段階 | 内容 | 終わりの条件 | 状態 |
|---|---|---|---|
| 0 | 準備（この台帳・方針・再開コマンドを作る） | 3 つのファイルがコミットされている | 済 |
| 1 | **目的の確定** | 目的が下の「目的」に 1〜3 行で書かれ、オーナーが合意している | 済 |
| 2 | **棚卸しと補完監査** | §3 の行がすべて「済」か「見送り」になっている | 済 |
| 3 | **計画の確定** | §4 の行がすべて「済」で、オーナーが承認している | 済 |
| 4 | **実行** | §5 の行がすべて「済」「見送り」「保留」のいずれかになっている | 未着手 |
| 5 | 片付け | 計画書・監査記録を `docs/history/` へ移し、受付箱の残りを `docs/issues.md` に移している | 未着手 |

### 目的

<!-- 段階 1 で書く。前回の計画書の目的は「将来の AI エージェントが誤解せず、最小の探索で正しい変更ができる状態にする」（計画書 §0.1）。
     同じ目的を引き継ぐのか、変える・足すのかをオーナーに確かめる -->

前回の計画書 §0.1 の目的を引き継ぐ（2026-10-02 オーナー合意）。
**将来の AI エージェントがコードを誤解せず、最小の探索で正しい変更ができる状態にする。外から見える振る舞いは変えない。**
評価基準は計画書 §0.1 の 4 つ（矛盾が無い・正典パターンが一意・派生値と副作用が辿れる・探す手数が少ない）。

### 状態の書き方

- `未着手` → `済`（成果物と同じコミットで書き換える）。`作業中` はコミットしない。
  中断されたかどうかは、作業ツリーに未コミットの変更があるかで判断する。
- `見送り`: やらないと決めたもの。理由を備考に書く。
- `保留`: オーナーの判断待ち。何を判断してほしいかを備考に書く。

## 3. 段階 2: 棚卸しと補完監査

### 3.1 棚卸し（既存の監査記録 8 本の指摘 154 件を、いまの HEAD に照らして仕分ける）

各単位の手順:
1. 監査記録を読む。
2. `git diff a04f375..HEAD --stat` で、指摘の対象ファイルのうち変わったものだけを開いて確かめる。
3. 指摘を「有効 / 陳腐化 / 重複 / 要確認」に分ける。
4. 結果を、その監査記録の末尾に「## 棚卸し（<HEAD のハッシュ>）」として足す。有効以外の指摘だけを列挙すればよい。
5. 記録の「未確認のまま残した範囲」のうち、段階 1 の目的に照らして見る価値のあるものを §3.2 に行として足す。

| ID | 対象 | 推奨 effort | 状態 | コミット | 備考 |
|---|---|---|---|---|---|
| B-01 | `audits/models.md`（M- 21 件） | high | 済 | `ae25a82` | 陳腐化 0・重複 3 組・要確認 5（うち M-07 は実測で決着済み）。A-01〜A-03 を足した |
| B-02 | `audits/controllers-views.md`（C- 23 件） | high | 済 | `ce74da5` | 陳腐化 0・重複 4 組・要確認 3。A-04〜A-06 を足した |
| B-03 | `audits/javascript.md`（J- 20 件） | high | 済 | `8da8a6f` | 陳腐化 0・重複 2 組・要確認 3（すべて §7.1 行き）。J-20 を確認済みに格上げ。新しい A 行は無し |
| B-04 | `audits/stylesheets.md`（S- 13 件） | high | 済 | `21483dd` | 陳腐化 0・重複 3 組・要確認 3。S-09 の前提を routes で確認した。A-07 を足した |
| B-05 | `audits/db-config.md`（CFG- 18 件） | high | 済 | `4610ead` | 陳腐化 0・重複 5 組・要確認 3。main にブランチ保護が無いことを確認した。A-03 を見送りにした |
| B-06 | `audits/test.md`（T- 19 件） | high | 済 | `d5a1376` | 陳腐化 0・重複 3 組・要確認 3。他の単位から預かった 6 点を決着させた。新しい指摘 T-20 を足した。新しい A 行は無し |
| B-07 | `audits/docs-guides.md`（DOC- 16 件） | high | 済 | `a668f8c` | 陳腐化 0・重複 5 組・要確認 2。コミットされた README・/expand を DOC-17〜20 として足した（§7.6 から対象に戻る）。A-08・A-09 を足した |
| B-08 | `audits/docs-specs.md`（SPEC- 24 件） | high | 済 | `de84dcf` | 陳腐化 0・重複 5 組・要確認 3。SPEC-13 をコードで確認した。A-05 を広げ、A-10・A-11 を足した。記録の文書の照合は見送り、P-01 で扱いを決める |

### 3.2 補完監査（棚卸しで見つかった未確認の範囲と、目的が変わって新たに見る範囲）

<!-- B の各単位と段階 1 の結果から、行を足す。1 行は 3〜5k 行以内に収める。
     成果物は audits/supplement/A-xx.md（1 単位 1 ファイル。サブエージェントが並行で書いても衝突しない）。
     指摘の ID は単位ごとに A01-1, A01-2 … と振る（既存の M- / C- などの通し番号とは衝突させない） -->

| ID | 対象 | 規模（行） | 推奨 effort | 状態 | コミット | 備考 |
|---|---|---:|---|---|---|---|
| A-01 | 派生値をビュー・ヘルパ・JS で再計算していないかの網羅確認: `app/helpers/stats_helper.rb`・`app/javascript/controllers/feature_range_controller.js` | 539 | high | 済 | `6f59f21` | B-01 から。B-02・B-03 のどちらでも覆われていなかった。JS 側は target_start の計算がサーバの規則と合っているかだけを見る 。指摘 7 件（A01-1〜7）。A01-1・A01-2 は外部振る舞いに関わる（target_start の検証が無い）。A01-5 の 818px はリーダーが裏取りした |
| A-02 | `MorphemeCloud`・`ShareCardTypesetter` の内部コメントが実装と合っているか | 648 | high | 済 | `0f0b541` | B-01 から（冒頭しか見ていない）。指摘 10 件（すべてリスク低）。コメントは概ね正確。A02-1・A02-10 は潜在的な不具合で §7.1 行き |
| A-03 | `app/models/seed_catalog.rb` の 41-254 行・`lib/tasks/dev_samples.rake`・`db/seeds.rb` の精読 | 533 | high | 見送り | `4610ead` | B-01 から。CFG-05〜CFG-07 で覆われていた（`audits/db-config.md` の棚卸しを参照） |
| A-04 | 管理ビューの精読: `app/views/admin/` の candidates・tags・annotation_decks・bulk_proposal_approvals・annotation_proposals・word_candidates の全ファイルと、annotations の `_proposal*`・`_feature_fields`・`_new_master`・`_variant_fields` | 1,296 | high | 済 | `96551ce` | B-02 から（grep で拾っただけ）。35 ファイルを読み通し、指摘 15 件。A04-1（特徴の再調査の書き出しで、日本語のみの絞り込みが外せない）はリーダーが確認した管理画面の不具合 |
| A-05 | 統計・共有パーシャルの精読: stats の `_origins`・`_sound_breakdown`・`_sound_matrix`・`_vowel_graph`・`_feature_ranking`・`_entity_cell`、shared の `_kana_ring_art`・`_radial_art`・`_brand_mark`、共有カードの SVG。あわせて stats.md §4〜§8 と実装の照合 | 約 650 | high | 済 | `fbe6a83` | B-02・B-08 から。stats.md §4〜§8 の 47 項目を照合（一致 39・不一致 5・一部一致 3）。指摘 12 件。エスケープの漏れは無し |
| A-06 | マスタを新設する経路の正規化と検証: `ProposedMasterCreation`・`TagKind`・`Genre`・`concerns/tag_master.rb`（C-20 の裏取り） | 301 | high | 済 | `e5d57c0` | B-02 から。指摘 7 件。C-20 は確認済みに格上げ（ただし本番の経路は seed を入れて 4 系統で、外部振る舞いへの影響は「あり（管理画面だけ）」に訂正）。照合順序をリーダーが MySQL 8.4.10 で実測した |
| A-07 | 逆方向の照合: ビュー・ヘルパ・i18n・JS が付けるクラス名のうち、CSS に定義が無いものを洗い出す（例: `.stats-header`・`.flash--notice`・`.proposal-json`）。スクリプトで機械的に出して、意図的なもの（JS のフック用など）と残骸に分ける | 全ビュー・JS | high | 済 | `ffb0664` | B-04 から。1 回目は 2026-10-02 に利用上限で途中終了し、成果物が残らなかったのでやり直した。静的に名前が分かるクラス 811 種のうち CSS が無いもの 53 件（フック 20・誤検出 2・残骸 2・判断不能 29）。指摘 5 件 |
| A-08 | 注釈スキルの `schema.json`・`example.json` と `AnnotationProposalImport::PAYLOAD_KEYS`・`ProposalApplication` の突き合わせ（M-05 の食い違いに 4 か所目が無いか） | 369 | high | 済 | `1c07bbe` | B-07 から。指摘 10 件。M-05 の 3 か所に加えて、キー一覧を持つ場所が 5 つあった（A08-1）。genre_new・target_start が黙って捨てられる |
| A-09 | data-model §8「一覧・検索・sitemap・API・統計のすべてが公開スコープを通る」の全経路の確認。公開側のコントローラ・ビュー・ヘルパ・統計の各クエリが `Word.annotated` / `WordSense.published` を通るかを洗い出す | 約 3,000 | high | 済 | `9c45384` | B-07 から。未公開語の漏れに関わるので優先度が高い。指摘 3 件。公開判定そのものの漏れは無い。公開を取り消した語がキャッシュに最大 1 日残る（A09-1）が、sitemap・llms-full については性能のための意図的な割り切りとコメントに書かれている。許容するかを P-04 でオーナーに聞く |
| A-10 | design.md の未照合の節（§5.1 フッターの細部・§5.6 入力部品・§6 タップ領域・§7・§9.2〜9.3・§10.1.2〜10.1.3）と CSS・レイアウトの照合 | 約 300（文書）＋該当 CSS | high | 済 | `1110261` | B-07・B-08 から。68 項目を照合（一致 57・不一致 6・実装に無い 1・文書に無い実装 3・未確認 1）。指摘 11 件。ΔRGB の式がテストと文書で違う（A10-1）のはリーダーが確認した |
| A-11 | annotation-guidelines.md と、注釈・再注釈・読み・拡張・収穫の各 SKILL.md、SeedCatalog のマスタの突き合わせ | 289（文書）＋スキル | high | 済 | `1483d2f` | B-05・B-08 から。指摘 13 件。マスタ名は概ね実在（外れ 3）。語種・ジャンル・特徴の規則は注釈スキルにしか無く、正の所在が文書と食い違う（A11-1） |

参考（2026-10-02 時点の行数）: app/models 5,965 / app/services 324 / app/controllers 2,016 / app/helpers 1,157 /
app/views 5,243 / app/javascript 2,219 / app/assets/stylesheets 8,127 / config 2,445 / lib 243 /
test 10,177 / docs 7,446 / .claude 1,419

## 4. 段階 3: 計画の確定

| ID | 内容 | 推奨 effort | 状態 | コミット | 備考 |
|---|---|---|---|---|---|
| P-01a | 計画書の改訂（1/4）: 冒頭・§0 前提・§1 ベースライン・§2 監査の概要（棚卸しと補完監査の結果）・§3 横断的な発見 | max | 済 | `af1a253` | P-01 を 4 つに分けた（1 単位が 5 時間枠の 1/3 を超えないように。STRATEGY §2.3）。行番号は a04f375 から変わっていない（コードの差分が無い）ので、合わせ直しは要らない。あわせて、計画書の改修項目の種類を「段階 0〜4」から「区分 T0〜G4」に改めた（台帳の「段階」と名前が衝突していたため） |
| P-01b | 計画書の改訂（2/4）: §4 正典パターン（補完監査で決まった正典と、§4.7 の正典表の追加） | max | 済 | `0a130b2` | 印は集計クラスが決める・提案 JSON のキーの正・公開スコープ・パーシャルの strict locals・管理画面の共有部品・JS のフック・クラス名の付け方・フレーム幅・ΔRGB の式・マスタ名の正規化と一致判定・用語「言語学的特徴」・数値のコメントを足した。§4.7 の正典表を 9 行増やし、§4.8（調査スキルとアプリの境界）を新設した |
| P-01c | 計画書の改訂（3/4）: §5 改修項目（既存の項目への追加と、新しい項目） | max | 済 | `b66420c` | 既存の 20 項目に補完監査の分を足し、新しい 8 項目（T0-13・T0-14・D1-18〜D1-21・R2-07・C3-24）を足した（計 71 項目）。§0.2 に管理画面の文言の線引きを足した。D1-12・D1-14・C3-07 は大きいので、P-03 で台帳に写すときに分ける |
| P-01d | 計画書の改訂（4/4）: §6 実行順序・§7 実施しないこと・§8・§9 対応表・§10 オーナーへの質問 | max | 済 | `e2a8071` | §6 に第7群（オーナーが選んだ振る舞いの変更を別 PR で直す）と台帳への写し方を足した。§7 に補完監査の分を振り分け、§7.6 を廃止し、§7.8（性能）を新設した。§8 は台帳の受付箱へ移した。§9 に補完監査 93 件の対応を足し、全指摘 252 件が対応していることをスクリプトで確かめた。§10 の質問を 5 つにまとめた |
| P-02 | 反証レビュー: サブエージェント 1 体に計画書を読ませ、「振る舞いを変えてしまう項目」「前提が誤っている項目」「抜けている依存関係」を挙げさせる。成果物は `audits/plan-review.md` | max | 済 | `3d0872f` | 指摘 16 件。公開の出力を変える 3 件（PR-1 今日の一語・PR-2 円環交差数の保存列・PR-7 横棒の丸め）と、既存テストを壊す削除 1 件（PR-3）が重い。PR-1・PR-3・PR-7 はリーダーが確かめた。D1-20 と C3-24 の「要確認」はレビューで決着した |
| P-03a | レビュー（P-02）の 16 件を計画書に反映する | max | 済 | `a4a167a` | P-03 を 2 つに分けた（STRATEGY §2.3）。特性テスト T0-15〜T0-21 を足して 78 項目にした。群の順序を「特性テスト → 残骸の削除」に入れ替え、第5群を C3-12 の後で区切った。実行ではサブエージェントを使わず直列にする。§0.2 に公開のテキスト出力・HTTP の鮮度判定と、backfill の例外を足した。§4.7 に節番号を変えない決まりを足した |
| P-03b | §5 の改修項目を台帳 §5 に書き写す（ID・群・1 行の内容・推奨 effort。大きい項目は a/b に分ける。計画書 §6「台帳への写し方」） | max | 済 | `fef3baa` | 78 項目を 92 行に写した（9 項目を分けて 90 行、手順の行 E-00・E-01 を足した）。max は C3-10・C3-12〜C3-18 の 8 行 |
| P-04 | **オーナーの承認**（計画書 §10 の 5 つの質問に答えてもらう。A09-1・A10-1・SPEC-19 などの個別の判断も §10 と §7.5 にまとめてある）。承認されるまで段階 4 に進まない | — | 済 | `e08c2f7` | 2026-10-03 に「推奨通り」で承認。推奨を添えていなかった S-01 は保留、A11-5 は正典どおりガイドラインを正とした。回答の全文は計画書 §10.1 |

## 5. 段階 4: 実行

<!-- 並びは計画書 §6 の実行順序どおり。上から順に進める。1 行 = 1 コミット以上。
     項目の中身（何をなぜ直すか・影響ファイル・完了条件）は計画書 §5 の同じ ID の行にある。a / b などは 1 項目を分けたもの。
     E- の行は項目ではない手順。実行はサブエージェントを使わず直列で行う（計画書 §6） -->

| ID | 群 | 内容（1 行） | 推奨 effort | 状態 | コミット | 備考 |
|---|---|---|---|---|---|---|
| E-00 | 開始前 | 合格判定（計画書 §0.3）を一度通して、ベースラインを取り直す。結果を作業ログに書く | high | 済 | `285830a` | 2026-10-03、HEAD `e08c2f7`（コードは a04f375 と同じ）。rubocop 310 files・違反 0 / brakeman 警告 0 / bundler-audit 0 / importmap audit 0 / `bin/rails test` 785 runs・15301 assertions・失敗 0・skip 1（rsvg-convert） / `bin/rails test:system`（Chrome 154.0.8037.92）26 runs・217 assertions・失敗 0 |
| D1-01 | 第1群 | デプロイと CI の実態（main への merge = 本番デプロイ、seed の改名、本番の DB 接続）を CLAUDE.md・overview・cppmtm・デプロイ設定のコメントに書く。`cap -T` を通す | high | 済 | `99576be` | `cap -T` と YAML の読み込みを確認。合格判定は全部通過（test:system は 1 回目に 1 件失敗したが、どのテストかを記録し損ねた。続けて 2 回再実行して 2 回とも 26 本・失敗 0。変更はコメントと文書だけ） |
| D1-02 | 第1群 | 合格判定コマンドを、動く形に直す（CLAUDE.md・overview・cppmtm・README） | high | 済 | `e4bc1a7` | 合格判定コマンドの正を CLAUDE.md に置き、overview §9・README・cppmtm はそこを指す形にした。`db:prepare` が新しい DB で schema.rb を読み込むことは Rails 8.1.3.1 の実装で確認（CFG-09 の推測を確認済みに）。`CI=1 bin/rails test` が通ることも確認。合格判定は全部通過 |
| D1-03 | 第1群 | 照合順序の記述を、計画書 §1 の実測に合わせる（as_ci の一覧は data-model §6 だけに置く） | high | 済 | `bbb27cc` | as_ci の一覧と実測表を data-model §6 に置き、CLAUDE.md は参照だけにした。「as_ci のままだと清濁が畳まれる」は誤りと実測で確認（REPLACE・REGEXP_REPLACE は、かなについては as_ci でも bin と同じ。M-07 を決着）。char_type_pattern で「あ」と「ア」が同一視されることを書いた。合格判定: test:system は 1 回目に console_test:189 が落ち、全体の再実行で 26 本・失敗 0（このテストは単独だと変更前でも毎回落ちる。受付箱へ） |
| D1-05 | 第1群 | CLAUDE.md の規約文（認証・ジョブ・system テスト）と、README のジョブの行を実態に合わせる | high | 済 | `c9428c6` | 認証の既定・ジョブが無いこと・system テストの対象・未ログイン拒否のテストの所在を CLAUDE.md に、ジョブの行を README に書いた。DOC-09 が挙げた overview §3 の曖昧な記述も同じ指摘の範囲として直した（計画書の影響ファイルからは漏れていた）。合格判定は全部通過 |
| D1-06 | 第2群 | 調査スキルと research/README の「この後の流れ」を現行のフローに合わせる（/expand を含む） | high | 済 | `0e51b9a` | 収穫・拡張・表記・読みのスキルの旧フロー（上部リストを次のスキルへ・重複は step3 が弾く）を、research/README の「使う順番」を指す形に直した。/expand の「この後の流れ」の節はすでに現行だった。annotation の API のホスト・ガイドラインの運用・README の /expand の収集軸（A11-10）・ja.yml の取り込み欄の例文（senses 形式）も直した。合格判定は全部通過。claude.ai 用のスキル束の再生成は D1-20 の後にまとめてオーナーに頼む |
| D1-19a | 第2群 | ガイドライン（読みの数え方・確信度の定義・規則の正の所在）と注釈スキルの食い違いを直す（A11-1・3・4・6・7・8・9・13） | high | 済 | `bb1ca73` | ガイドラインに、正とする範囲・§0 の読みの数え方・§8 確信度を足し、運用の節を直した。注釈スキルの手順1（語義の読み）・特徴の対応表（3 行と正式名）・熟字訓の例（glossary に合わせる）・手順9（§3 の参照）・別表記の類型（5 の言い換え・旧称・俗称）・確信度を直した。example.json の上手→ジョウズの熟字訓を外し、seed_catalog の注記に対応表を並べた。research/README の「正」の範囲も直した（A11-1 の README の分）。A11-1 の reannotation・A11-3 の harvest／expansion の分は D1-19b。合格判定は全部通過 |
| D1-19b | 第2群 | 再注釈・読み・表記・拡張・収穫のスキルと README の食い違いを直し、ガイドラインの写しを参照に置き換える（A11-2・5・11・12）。スキル束の再生成はオーナーに頼む | high | 済 | `17cd454` | 再注釈スキルの正の所在（立項スコアは §2・確信度は §8）と入力例の読み、target_reading の切り出し方（「、」連結・字種そのまま。A11-2）、/harvest のモーラ→文字数と委ね先・発表直後の名称（A11-5。ガイドラインを正）・例の差し替え、/reading の確信度を §8 に、§2・§4・§6 の写しを参照に、マスタの列挙に日付と現況の出どころ、ギリシャ語→アラビア語、用語を「言語学的特徴」に統一（7 ファイル）。合格判定は全部通過 |
| D1-20 | 第2群 | 提案 JSON の取り決め（genre_new・target_start・required・再注釈の注意）を、スキルの文書と schema.json に事実どおりに書く | high | 済 | `b9cbe1c` | genre_new は参考情報、target_start は反映で使われないと書いた。schema.json に required と allOf（語義の 4 項目・立項スコア・スコア 3 以上の senses・3 以下の entry_notes・low の notes）を足し、example.json が通ること（エラー 0）と、崩した例が弾かれることを jsonschema で確かめた。スコア 1〜2 の語は senses を省いてよいと書いた（例 125 と取り込みの実装に合わせた）。再注釈の「外す結論は JSON では伝わらない」、特徴だけの書き出しは単一語義の語だけ正しく反映されることを書いた。**D1-06・D1-19・D1-20 でスキルを直したので、claude.ai 用のスキル束の再生成とアップロードをオーナーに頼む**。合格判定は全部通過 |
| D1-07 | 第2群 | 文書間の参照切れと、置き場所の食い違いを直す（changelog に #162〜#164 を足すなど） | high | 済 | `b34eb08` | Issue 80・81・56 の参照先を changelog に、issues.md の行番号の参照をシンボル名に、plotly の配信の記述（pin ではなく manifest の link_tree）を直し、improvements.md が辿れないことを注記した。overview の完了記録の置き場所と CSS の一覧（candidates.css）、.gitignore のスキル名、changelog の #162〜#164 を直した。issues.md:336 の「(確定事項・Issue 74)」は指す先が見つからず未対応（Issue 74 はクロール導線の整理で、折り畳みの判断ではない）。overview のコードの地図の欠け（CFG-11）は G4-03。合格判定は全部通過 |
| D1-08 | 第2群 | 否決・失効した判断を今も指示している記述を直す（growth-strategy・issues・performance-report・stats.md） | high | 済 | `79dda9d` | growth-strategy の遡及付与（確定事項 37）・Bing（確定事項 33）・解禁予定日の宿題・文言の出どころ（pages.about.* と og_default.py の LEAD）・fragment cache の呼び名を直した。issues.md の確定事項 16・18 に失効の注記、performance-report の冒頭に §8 のその後、stats.md の「最頻のみ --chart」を直した。changelog の Issue 48 の見出しは記録なので書き換えず注記を添えた。合格判定は全部通過 |
| D1-09a | 第2群 | design.md・CLAUDE.md を CSS の実態に合わせる（ゼロ埋めの例外、`--bg` と面の段、章の罫、管理画面の上書きとダーク未対応） | high | 済 | `5ae8f46` | ゼロ埋めの例外（.entry-range の 001–100）、--bg の実際の用途（地は --surface。ドロワー・操作バー・ホームの検索ボタン・反転文字・color-mix の下地）、章の罫を .sheet を含めた 5 箇所に、管理画面の上書き（トークン＋一部のコンポーネント＋専用の 2 色）とダーク未対応を、design.md と CLAUDE.md に書いた。CSS 側のコメントの同じ食い違いは D1-16。`design.md §`・`stats.md §` の参照 160 件がすべて実在することを確かめた。合格判定は全部通過 |
| D1-09b | 第2群 | design.md を CSS の実態に合わせる（行間・見出し・区切り線と囲い・§5.3 の矛盾・動きの例外・検索条件の数・古い記述）。節番号は変えない | high | 済 | `7748b9b` | 見出しの行間 1.75・級数（ヒーロー 26px・ページ見出し 24px）・10px の例外、区切り線（gap: 1px）・行の角丸・語義カードとランキングの板（1px --border の囲い）、動きの例外（250ms 以下の状態の動き）、検索条件の数（書かずに出どころを指す）、Issue 84 の記述、管理画面の計測値（2 回の計測があることを書いた）を直した。CLAUDE.md の動きの節にも例外を足した。節の参照 161 件はすべて実在。合格判定は全部通過 |
| D1-10a | 第2群 | stats.md の本文を実装に合わせる（リンク先・順序・章題・拍位置・明度・地・操作規則・データの出どころ・件数の単位） | high | 済 | `47a4703` | リンク先（/words。/search ではない）、ページの並び、各章の画面の見出し（ja.yml のキー）、§2 の注記、再集計の文言と奥付、§4 の集計（Ruby で週ごと・点は末尾だけ）、§6 の 5 値の実際と明度、§7 の位置（vowel_pattern の添字）・選んだ鎖・控えだけ外す規則・スペクトルの打ち切り・頭子音の出し方、§8 の件数の単位、チントの式が 3 通りあることを、実装に合わせて書いた。節番号は変えていない（参照 161 件はすべて実在）。合格判定は全部通過 |
| D1-10b | 第2群 | コメントの § 参照を「stats.md §N」「統計ページ §N」に書き分ける（`grep -rn '§[0-9]'` の全件を確かめる） | high | 済 | `df5d81d` | app・lib・config・test の「§」の参照 100 件を全件確かめ、文書名の無い 37 件と、紙面の章を「stats.md §N」と書いていた 12 件を書き分けた（紙面の章＝統計ページ §N、文書の節＝stats.md §N、design.md の節＝design.md §N）。決まりは stats.md の冒頭に書いた。章名はコメントでも画面の見出しに揃えた。節の参照 158 件はすべて実在。合格判定: test:system は 1 回目に既知の console_test:189 が落ち、再実行で 26 本・失敗 0 |
| D1-11 | 第2群 | genres.md と SeedCatalog の関係（正は SeedCatalog）と、小分類の追加経路の記述を直す | high | 済 | `656e7b5` | seed_catalog.rb の「出典: docs/genres.md」を正の向きに、存在しない RENAMES を種類ごとの *_RENAMES に直した。genres.md に手作業の写しであること（Issue 85 で生成に）と、小分類の実際の追加経路 3 つ（タグ統括管理では追加できない）を書いた。合格判定は全部通過 |
| D1-12a | 第2群 | モデル・サービスのコメントを実装に合わせる（初版の分: unannotated・公開スコープの名前・種別ラベル・テスト用の注記など） | high | 済 | `1388c5a` | 非 ActiveRecord のクラス 49 本とサービス 3 本に「種別:」の行を置き、計画書 §4.1 の語彙に揃えた（WordRanking・SearchRegexp の「値オブジェクト」の誤りを直した）。unannotated の説明・公開スコープの名前・ProposalApplication の保存・重複チェック 3 実装の違い・KanaRow の波及・SiteStatistics の冒頭とタグクラウド・語種名の例・将来の差し込み口・update_sql の参照元・DECISIONS への参照・register と annotated? の意味・読みの改行の 2 通り・テスト専用の 9 か所を直した。変更行がすべてコメントであることを確かめた。合格判定は全部通過 |
| D1-12b | 第2群 | モデルのコメントを実装に合わせる（補完監査の分: MorphemeCloud・ShareCardTypesetter・ProposedMasterCreation・ProposalApplication・SiteStatistics の total） | high | 済 | `1b6d68b` | MorphemeCloud（最後の pack の実際・落ちる語・実測値の出どころ・用語・Z と記号の幅・相互参照・top はテスト用）、MorphemeFrequencies（見本→ワードクラウド・壊れた JSON の方針）、ShareCardTypesetter と ShareCardRenderer（割りやすい所の実際・書体の前提）、WordShareCard の字面、SiteStatistics（拍位置・件数の単位・total はテスト用）、ProposedMasterCreation の語種、seeded? の完全一致、ProposalApplication の反映の意味の表を直した。経緯の数値「60 件中 23 件」は stats.md へ移した。変更行はすべてコメント。合格判定は全部通過 |
| D1-13 | 第2群 | 暗黙の前提をコードに書く（コールバックを通らない更新・target_start・マスタ名の正規化と衝突・WordBatch など） | high | 済 | `ba58a72` | update_all の 4 経路、RefreshesWordMetrics の発火条件、ExpansionImport の savepoint 無しの続行、収録基準はモデルで検証しないこと、JAPANESE_ORIGIN_NAME の依存、公開状態の 2 列、プロセス内のメモ、target_start の前提、マスタ名の正規化と衝突の扱い（その場追加・タグ統括管理・新設候補・seed）、find_or_create_by! の Rails 8.1 依存、entry_score の範囲外の食い違い、不完全な提案の黙った除外、WordBatch、run_import の前提をコメントに書いた。WordCandidateIntake のコメントは初版の計画書で不採用にしたので触っていない。変更行はすべてコメント。合格判定は全部通過 |
| D1-14a | 第2群 | コントローラ・ビュー・ヘルパのコメントを実装に合わせる（初版の分） | high | 済 | `2c43eb0` | 計画書 D1-14 の初版の分（C-23・SPEC-15・SPEC-07・C-01・C-03・J-11・S-08・C-22 の nonce）を直した。「words#feed」「新着より上」、home/index の重複、words/index のファセット一覧（INDEXABLE_FACET_KEYS を指す形に）、genres/index の数の定義（3 通りあることを書いた）、「一覧は public でキャッシュ」（word_requests_controller・words/index）、太字（3 か所）・アクセント（統計の 4 か所と icons_helper）・印章、stats_helper の「2周期」と「見立て」（_length_chart も）、_sound_matrix の 11×11、_entry_row の組み方、words/show の §5.4、searches_controller の許可パラメータの違い（words_controller から相互参照）、CSP 未設定の前提（layout と _analytics）、テーマ復元 2 か所の相互参照（layout と theme_controller.js）、theme-color の既定値。admin/_nav の「アクセント色」は --admin-accent が実在するので直していない。変更行はすべてコメント（ERB は Erubi で HEAD と出力が同じことを 16 ファイルで確かめた）。§ 参照 158 件すべて実在。合格判定は全部通過 |
| D1-14b | 第2群 | コントローラ・ビュー・ヘルパのコメントを実装に合わせる（補完監査の分: 統計・円環・登録予定単語・新設候補の案内・ワードマーク）。`share_cards/word.svg.erb` には触れない | high | 済 | `fa96bb8` | A01-4（波形バーと数字の壁で最頻の決め方が違い、「30+」の合計が単一の値の最大を超えると食い違う。stats_helper）、A01-5（グラフ幅は式と 1,148px、色は CSS で線の太さと濃さはヘルパ、ツリーマップは 767px 以下で CSS だけ 3:5）、A05-10（頭子音・特徴・エンティティ型の「先頭行＝最多」の前提と :first-child、集計対象の出どころが 2 通り）、A05-9（top の 3 つの意味。stats_helper と _vowel_graph）、A05-5（図のキャプションは標識の規則の対象外。design.md §5.8 への追記は D1-21）、A05-6（円環 3 テンプレートの相互参照と違い。_kana_ring_art・_brand_mark・WordShareCard）、A04-6（「元の語」の判定 3 通りと食い違う条件。admin/candidates/_word・lists/show）、A06-5（_proposal_sense のコメントと ja.yml の失敗時の案内を「入力欄の『＋ 追加』から」に。管理画面の文言 1 行で、テストは I18n.t で比べるので変わらない）、A10-7（layout のフッターの古いワードマークのコメント 2 行を削除）。ja.yml 以外の変更行はすべてコメント（ERB は 10 ファイルで出力が HEAD と同じ）。`share_cards/word.svg.erb` には触れておらず、開発 DB の 5 語で共有カードの digest が前後で同じことを確かめた。§ 参照 158 件すべて実在。合格判定は全部通過（システムテストの assertion 数は 220→219。失敗 0） |
| D1-15 | 第2群 | JavaScript のコメントを実装に合わせる | high | 済 | `508b8f8` | importmap.rb・controllers/index.js の「公開ページでは使わない」（28 本を遅延読み込み、ヘッダーの 3 本は毎ページ）、Plotly を意図してピンしないこと（importmap.rb・manifest.js・genre_sunburst。版・audit の対象外・更新時の確認）、application.js の window.Stimulus（システムテストの wait_for_stimulus）、nav_drawer の「検索パネル」、char_type のキー 7 つ、auto_submit は付けた form 自身を送ること、check_all の 2 つの用途、queue_nav の先頭へのスクロール、range_slider・feature_range の「アクセント」（--text・--bg-tint）、genre_sunburst のパレットの直書きと --bg、sense_cloner の nested attributes 依存、js-genre-* はテスト用のフック（_sense_fields。_bulk_annotation 側は未参照と注記）、サーバ側の規則の正（vowel_graph の URL 形式、char_type の畳み込み、reading_format のカタカナ、sense_completeness の「最低限」、reading_counter の trim と strip の差）、feature_range の restoreOne の target_start の前提（A01-1）、vowel_graph の操作規則は stats.md 統計ページ §7 を参照するだけにし、3.2 = GRAPH_MAX_EDGE を書いた（A05-4・A05-7）。A05-7 の _vowel_graph.html.erb の「2 つ押して」もここで直した。CSS の同じ記述は受付箱から D1-16 へ。JS の trim は全角空白を落とし Ruby の strip は落とさないことを node と ruby で確かめた。変更行はコメント（と importmap.rb の空行 1 つ）だけ。ERB は 3 ファイルで出力が同じ。manifest は今も plotly.min.js を link し、importmap に Plotly が無いことを runner で確かめた。§ 参照 159 件すべて実在。合格判定は全部通過 |
| D1-16a | 第2群 | CSS のコメントを実装に合わせる（tokens・base・application・admin・annotate・layout の冒頭と方針、i18n の中のクラス名、読み込み順・記述順に依存する規則の両側の注記） | high | 済 | `a8cc89a` | 分量が多いので D1-16 を a・b に分けた（b は components.css の古いコメントと補完監査の分）。tokens.css の冒頭を計画書 §4.4 の「直書きしてよい範囲」に、面（--bg は一段淡い面でかつての地、--surface が本文の地）・--text-subtle の比（白地 5.6 / --bg 5.0 / --bg-soft 4.7 を計算で確認）・罫（二層）を直した。base.css の対象（.mono）と「ヘッダー(--bg)」。application.css に配置と読み込み順の意味（Sprockets のディレクティブと誤認されない書き方）。admin.css の方針（コンポーネントの上書きと 2 色、ダーク非対応）・shadow（公開側も --shadow-pop を使う。--shadow-soft は未参照）・--radius-sm・計測値の 2 つ目（design.md §10.2）。annotate.css の「青一色」「枠を緑に」（.ann-sense は border を持たないので border-color は効いていない。同じ記述の sense_completeness_controller.js と _sense_fields.html.erb も直した）・「アクセントの淡い面」。layout.css の「縦の基準線」。shiritori__char・cand-export__num の使用元（ja.yml のキー）。記述順の注記: .section-heading の 2 定義、.stats-grid の効いていない margin と 767px の gap、.label-en と .ring-art__caption、.mono と .entry-range（「001–050」も 001–100 に）、admin-words-table の色（components 側は効かない）、annotate.css の iOS 対策（実際は input[type="text"] の特異度で決まり、順序に頼っていない）。CSS はコメントを除くと 8 ファイルとも HEAD と同じ（csscheck）、ERB は出力が同じ、JS はコメントだけ。コンパイルした application.css に 7 ファイルが同じ順で入ることを runner で確かめた。§ 参照 164 件すべて実在。合格判定は全部通過 |
| D1-16b | 第2群 | CSS のコメントを実装に合わせる（components.css の古いコメント: SPEC-05 の「唯一」「4 箇所」、S-12・SPEC-15 の列挙。補完監査の分: A05-3 統計の地の --bg、A05-4 の 3.2、A07-4 既定の見た目の修飾子、A07-5 JS・テストも参照するクラス。受付箱の A05-7 の「2ノード」） | high | 済 | `3d67b31` | SPEC-05（「唯一」→ design.md §3 の 5 か所の 1 つ、「4 箇所」→ §3 に列挙した箇所）。S-12・SPEC-15 の列挙（語義パネルの「枠を持たない」、看板の「左揃え」「細い枠」、.section-title の「縦組み」、今日の一語の「角丸カード」、.home-column の「2カラム」、.word-flavor の「細罫の下」、.prose の幅、.label-en の「白抜きが成立する最小」、遷移グラフの「最多の1本だけ --chart」、ランキングの「見出し行は細罫」、リクエスト一覧の「未着手だけ色」、.data-table の「検索結果」、「ヘッダー検索」）。「アクセント」と書く公開側のコメントは、列挙外のものも含めて 21 か所すべてを実際の色（--text・--bg-tint・--chart・--text-muted）に直した（SPEC-15 は類として挙げている。管理画面の「アクセント色」は実在する --admin-accent なので触っていない）。規則の無い孤立したコメント 5 行（円環の旧ダイアログの名残）と「太さ」も直した。.ring-art__value を図のキャプションの規則に合わせた（A05-5）。A05-3（§6・§7 の --bg は地だった頃の名残）、A05-4（3.2 = GRAPH_MAX_EDGE）、ツリーマップの 767px 以下の 3:5（A01-5 の CSS 側）、A05-10 の CSS 側（:first-child が並びに頼る）、A07-4（既定の見た目に任せる修飾子 7 種）、A07-5（JS も参照する見た目用のクラス 8 種）、受付箱の A05-7（「2ノード」→ 選んだ鎖）。CSS はコメントを除くと 3 ファイルとも HEAD と同じ（csscheck）。§ 参照 169 件すべて実在。合格判定は全部通過 |
| D1-17a | 第2群 | 設定・タスク・文書のコメントを実装に合わせる（INDEXING_ENABLED・puma・routes・stats.rake・backfill.rake・overview の外部コマンドの表・data-model の db/migrate） | high | 済 | `b472457` | 分量が多いので D1-17 を a・b に分けた（b はテスト側）。application.rb の INDEXING_ENABLED（解禁済み、値は見ず設定の有無で決まり REQUESTS_ENABLED と解釈が違う）。puma.rb に理由（preload_app! の分岐は単一モードでは効かない、パスは deploy_to の直書き、worker_timeout は初期コミットの Rails の雛形由来でクラスタモードにだけ効く。Puma の仕様からの判断で起動しての確認はしていない。コメントだけで設定値は変えていない）。routes.rb に「ログイン → 公開面 → 管理面 → 公開面の残り」の見出しと、公開 URL・クエリ名は変えないこと、apply_research の説明を足し、雛形の 1 行を消した。stats.rake の MeCab の前提を overview の表（「本番・CI」の列を新設）へ寄せ、「冪等」を counts は同じだがファイルは generated_at で変わる、に直し、SURFACES_FILE には公開語だけを渡すこと（A09-2）を書いた。overview の MECAB_DICT は ReadingExtractor にだけ効くことも直した（CFG-08）。backfill.rake の冒頭をいまの用途（修復）に。data-model に db/migrate のコメントは当時の記録で、articles の 2 本は雛形の試しである段落。変更はコメントと文書だけ（routes.rb の空行を除く）。合格判定: 静的検査と単体は通過、システムテストは admin_annotation_deck_test.rb:84（既知の不安定なテスト）が 1 回落ち、再実行で 26 件すべて通過 |
| D1-17b | 第2群 | テストのコメントを実装に合わせる（application_system_test_case の Google Fonts と sticky、backfill_task_test、管理画面のテストの空の見出し、word_requests テストの説明、fixtures の murder の読み、システムテストの入力手段（要確認: 実行して確かめる）、morpheme_frequencies_test の「朱」） | high | 済 | `575d5ce` | application_system_test_case の Google Fonts（アプリは読まないので、いまは保険として残すと書いた。T-20）と「sticky ヘッダー」（sticky なのは下端の操作バー）。backfill_task_test の「ずれは検出される」（verify は ring_crossing_count を見ない）。管理画面のテストの空の見出し 5 つを消し、word_requests テストのファイル説明から「認可」を外して admin_authentication_test を指した。fixtures の murder の読みがひらがなである意図（word_requests_controller_test が頼っている）。morpheme_frequencies_test の失敗メッセージの「朱」（期待値は変えていない）。要確認の入力手段は使い捨てのシステムテスト（scratchpad）で実測した: ログイン前は日本語・ASCII の fill_in・send_keys・Actions・ネイティブクリックがすべて届く。system_sign_in の後は、公開フォーム・一括登録・仕分けの行のどれでも届かなかった。Chrome のパスワード漏洩の警告（fixture のパスワード "password"）を切ったドライバでは届いたので、原因はそれ。この事実を ApplicationSystemTestCase の 1 か所に書き、reading_format・word_candidates のテストの注記をそこへ向けた（ドライバの設定は変えていない。受付箱へ）。変更はコメント（と空行・失敗メッセージ 1 つ）だけ。合格判定は全部通過 |
| D1-18 | 第2群 | 公開スコープの例外を data-model §8 に表で書き、公開の取り消しが最大 1 日遅れること（A09-1。許容に決まった）も書く | high | 済 | `797af66` | data-model §8 の「すべてがこのスコープを通る」を「原則として」に直し、§8.1 に例外 3 つ（ワードクラウドの事前集計ファイル、/search とファセットの見出しのマスタ全件、ホームのジャンル数）を、語の漏れにならない理由と注意つきの表にした。§8.2 に公開の取り消しが反映されるまでの遅れを、すぐ消える（詳細・一覧・Atom・共有カード。ただし版付きの共有カードは 1 年 immutable で配った画像は残る）／最大 1 日残る（llms-full.txt・sitemap.xml・/rankings・/stats）／数だけ残る、に分けて書き、オーナーが許容したこと、本番は memory_store で再起動で消えること、キャッシュを足すときの前提を書いた（各 TTL と cache_store はコードで確かめた）。published_words_digest.rb の冒頭と削除の段落に、取り消しも遅れに含まれ許容済みであることを書いた。Ruby の変更はコメントだけ。合格判定は全部通過 |
| D1-21 | 第2群 | design.md を実装に合わせる（補完監査の分: ΔRGB の式は最大差に決まった・タップ領域・ブレークポイント・標識の例外など）。節番号は変えない | high | 済 | `2f5a3c7` | §1 に ΔRGB の定義（R・G・B の差の最大値。オーナー判断）と既知の問題（テストは合計で測る、ダークの --bg-tint は最大差 16 で下限に届かない。計算で確認）を書き、§9.1・§10.1.3 の数値を定義に合わせた（11→7、22→16、59/53/44→59）。コード側の「ΔRGB 22」（tokens.css）と design_tokens_test の delta_rgb にも定義との違いを注記した（コメントだけ）。§1 の --text-subtle の比を白地 5.6／--bg 5.0／--bg-soft 4.7 に。§4・§5.6 の入力の focus に共通の :focus-visible も出ること。§5.1 の共有カードの割りやすい所を ShareCardTypesetter に合わせ、フッターのワードマークを消し、560px 以下の余白のずれと 1040px の 4 か所の直書きを書いた。§5.8 に標識の規則の例外 3 つ（ブランド名の右の英字・フッターの EST.・図のキャプション）と、日本語の見出しとの対の実際の組み方。CLAUDE.md の標識の行に「例外は design.md §5.8」を 1 行。§5.9 の .radial-art は目印だけ。§6 のタップ領域の実寸と、閉じたドロワー・ナビのランドマークの既知の問題。§7 を「広い幅が基底で max-width で上書き」に直し、検証幅に 1000px、表を畳むか横スクロールかの選び方、ブレークポイント 7 つの表（CSS の @media をすべて洗って作った）。§10.1.3 に表の行 hover が AA を割る既知の問題（4.19・4.08 を計算で確認）。§11（末尾に新設）にクラス名の付け方。既存の節番号は変えていない。§ 参照 173 件すべて実在。CSS とテストはコメントだけ。合格判定は全部通過。これで第1群・第2群がすべて済んだ |
| T0-01 | 第3群 | 公開 JSON API のキー集合と入れ子を固定する | high | 済 | `a688812` | 第1〜2群の切れ目では merge の指示が無いまま再開されたので、merge せずこのブランチで第3群に進んだ（2026-10-03）。words_api_test.rb に、詳細のキー集合（語・語義・特徴）と値（char_type_pattern・mora_count など 5 つ・ジャンルの id/name/level・entity_type）、ライセンスのハッシュ全体、ジャンルの無い語義（curry）で genre と entity_type が null・variants が [{surface, reading}] になること、一覧のキー集合・total_pages・語の id/surface/url/readings を足した（2 件追加・既存 1 件を拡張）。合格判定は全部通過 |
| T0-02 | 第3群 | 外部コマンドのフォールバックを固定する（MeCab 無しは PATH を空にして確かめる） | high | 済 | `93ef293` | share_cards_controller_test に「fetch が nil」と「語義の無い公開語（描けない語）」で /og-default.png へ回るテスト。reading_extractor_test に PATH を空にして [nil, nil] が返るテスト。morpheme_extractor_test は setup の丸ごと skip に掛からない MorphemeExtractorFallbackTest を新設し、PATH を空にして available? が false・[[], []] が返るテストを置き、mecab の要らない「空の入力」をそちらへ移した（重複させない）。ローカルには mecab があるので、PATH を空にしたテストは実際に退避の分岐を通っている。合格判定は全部通過 |
| T0-03 | 第3群 | 収録リクエストの、まだ固定されていない振る舞いを固定する | high | 済 | `571d4da` | word_requests_controller_test に 3 件足した。フォームの項目名（items_attributes の surface/reading、form_token、origin_path、ハニーポット）。期限切れのトークン（EXPIRES_IN を過ぎて発行）で 422 と expired の案内になり、レコードを作らないこと。受付中はホーム・検索 0 件の一覧（.empty-request）・About に /requests/new への導線が出て、受付停止中は 3 ページとも 0 件になること（出る側も確かめるので空振りしない）。上限値の定数化は計画書のとおり見送り。合格判定は全部通過 |
| T0-04 | 第3群 | 公開ページの、まだ固定されていない振る舞いを固定する（今日の一語はキャッシュの語数で選ぶことを含む） | high | 済 | `d7bb6e3` | home_controller_test に 3 件: ホームの検索欄が /words へ q を GET で送ること、今日の一語が日付で決まり翌日は別の語になること、キャッシュ（Rails.cache をテストの中だけメモリストアに差し替え）の語数 2 と実際の語数 3 がずれた日でもキャッシュの語数で選ぶこと（jd % 6 == 4 の日を使う。キャッシュを差し替えない版は落ちることを scratchpad で確かめた）。sitemaps_controller_test に <loc> の集合と順序（静的 8 件＋公開語）を丸ごと比べるテスト（/rankings を含む）。words_feed_test に FEED_LIMIT 件まで・絞り込みを無視・エントリの URL が本番ホスト。sessions_controller_test に、弾かれた管理画面の URL（クエリ込み）へログイン後に戻るテスト。合格判定は全部通過 |
| T0-05 | 第3群 | 多語義語の代表語義と、語義の順序を固定する | high | 済 | `33ef215` | 先頭（id が最小）の語義が 6 字・2 番目が 15 字の語を作り、いまの振る舞いを固定した。一覧の行は先頭の語義の文字数（6 字）を出し、読みは語義の順に「、」で並べる。詳細の語義カードは id の順。ホームでは「読みが長い言葉」の 1 位になる（並びは max_reading_length）が、看板と行に出る数は先頭の語義の 6（C-02 のずれ。C3-14 で変えない方針なので、いまの値で固定）。JSON の senses は id の順。words_controller_test・home_controller_test・words_api_test に 1 件ずつ。合格判定は全部通過 |
| T0-06 | 第3群 | 照合順序の帰結（一意制約・char_type_pattern の検索）を固定する | high | 済 | `f7ee13c` | word_test に、surface の一意性がひらがな⇔カタカナ（しゃーろっと）と小書き⇔並字（シヤーロット）を同一視し、清濁（ジャーロット）は区別するテスト。word_sense_search_test に、大小を区別しない文字種の検索では「ああ…」の語が「アア…」のパターンに当たり、区別する検索（utf8mb4_bin）では当たらないテスト。合格判定は全部通過 |
| T0-07 | 第3群 | `body.is-admin` の付き方を固定する | high | 済 | `144dd3d` | test/integration/admin_body_class_test.rb を新設。ログイン画面には付かず、管理画面（/admin・単語の管理・タグ管理）には付き、ログインしていても公開ページ（ホーム・一覧・詳細・About）には付かないことを 1 本で確かめる。合格判定は全部通過 |
| T0-08 | 第3群 | 検索スライダーの表示文言と hidden の値を固定する（system テスト） | high | 済 | `0e20ee0` | test/system/search_length_slider_test.rb を新設（1 回の visit）。初期は「10文字以上」で hidden は 10 と空、15〜20 で「15文字以上20文字以下」、同じ値で「20文字」、下限が上限を追い越すと上限も連れて動く（「25文字」）、上限 30 で「25文字以上」と max が空。つまみは値を入れて input を発火させる（ネイティブの range 操作に頼らない）。単独で 3 回流して安定。合格判定は全部通過 |
| T0-09 | 第3群 | tokens.css のダークの 2 ブロックの一致と、application.css の読み込み順を確かめる | high | 済 | `828e140` | design_tokens_test に 2 件。@media と [data-theme="dark"] の宣言が同じで、:root の --dark-* をすべて --X: var(--dark-X) で参照し、color-scheme が dark であること（片方から 1 行抜くと検出できることを同じ抽出で確かめた）。application.css の require が tokens → base → layout → components → annotate → candidates → admin の順で、require_self があり require_tree が無いこと。合格判定は全部通過 |
| T0-10 | 第3群 | 提案の取り込みと反映で捨てられるキーを固定する | high | 済 | `ab50129` | annotation_proposal_import_test に 2 件: トップレベルの reading・linguistic_features・sense_id は捨てられ（payload は meaning だけ）、旧形式の語義の読みは nil・特徴は空になること。senses の要素は genre_new・target_start・未知のキーごと丸ごと保持し、トップレベルの genre_new も保持すること。test/models/proposal_application_test.rb を新設して 2 件: 提案の target_start（5）は反映で使われず、組んだ特徴は nil で、保存すると先頭の出現（0）になること。SenseProposal に genre_new を読む口が無いこと。合格判定は全部通過 |
| T0-11 | 第3群 | `backfill:sense_metrics` が崩した代表値を元に戻すことを固定する | high | 済 | `312f40b` | backfill_task_test に 1 件。WordSenseMetrics.refresh! で正しい値を取ってから、update_all で全語の代表値（14 列）を崩し（崩れたことも確かめる）、タスクの後に 14 列が元どおりになること、curry の値（語義 1・別表記 1・最長 3・max_reading カレー）を固定した。合格判定は全部通過 |
| T0-12 | 第3群 | 名前と中身がずれているテストの名前を直し、名前が約束していた検証を足す | high | 済 | `ddc2ba5` | 名前を中身に合わせた（assert は変えていない）: admin/words の「単語を削除すると語義も消える」、word_sense_feature の「別の語義には同じ特徴を付けられる」、reannotation_export の「注釈の内容が保存された語でも…」（ReannotationExport#annotated? と Word.annotated が別の意味であることを注記）。名前が約束していた検証を新しいテストとして足した: 単語を削除すると特徴（murder の 2 件）も消えること、同じ語の別の語義になら同じ特徴・同じ該当部分（殺人）・同じ出現位置でも付けられ、同じ語義なら重複になること。T-12 のほかの項目（tag_kind の空の assert、word_requests の重複検証）は計画書の T0-12 に入っていないので触っていない（「朱」は D1-17b で済）。合格判定は全部通過 |
| T0-13 | 第3群 | 読みを変えて保存すると `reading_density` が追従することを固定する | high | 済 | `04f2448` | word_sense_metrics_test に 1 件。表記 3 字の語の語義の読みを 6 字から 9 字に変えて保存すると、after_commit で max_reading_length が 9 に焼き直され、STORED の reading_density が 2.0 から 3.0 になること。合格判定は全部通過 |
| T0-14 | 第3群 | 母音遷移の境界値（15 拍・位置 30 / 31）を固定する | high | 済 | `dd72545` | word_sense_search_test に 1 件: 並び 15 拍は条件に残り 16 拍は捨てる、拍位置 30 は残り 31 は捨てる（conditions? も false）。site_statistics_test に 1 件: 20 拍の読みがあっても層は 15 で打ち切り、最後の層の位置が 15、遷移は 14 区間。合格判定は全部通過 |
| T0-15 | 第3群 | og:image の版（`WordShareCard#digest`）を固定する | high | 済 | `f92f8eb` | word_share_card_test に 1 件。abc_murder の版 ba4090a8b4c0c919 と curry の版 081b6da5155bc686 を文字列で固定した（テスト環境で 2 回取って同じ値）。改修のあいだの特性テストで、残すかは G4-05 で決める。合格判定は全部通過 |
| T0-16 | 第3群 | 一括登録の調査 JSON で、形が不正な入力の扱いを固定する | high | 済 | `9678d98` | bulk_word_registration_test に 3 件（壊れた JSON とフェンス付きは既存のテストがある）: words の中の Hash でない要素（文字列・数値・nil）は黙って飛ばしてほかの要素を使いエラーにしないこと、調査 JSON が nil・空・空白だけならエラーにせず全行 mecab_only、words が配列でない・words が無い・トップレベルが配列なら research_error? が真で全行 mecab_only。合格判定は全部通過 |
| T0-17 | 第3群 | 公開一覧のページ送り（seed の引き継ぎ・nofollow）を固定する | high | 済 | `914c8ec` | words_controller_test に 1 件。公開語を 103 件（2 ページ）にして、既定の並びでは「次へ」が /words?page=2 で nofollow が無いこと、最後のページはリンクが「前へ」（page=1）の 1 本だけであること、シャッフル中（seed 指定）は sort・seed を引き継いだ page=2 のリンクに rel=nofollow が付くことを固定した。合格判定は全部通過 |
| T0-18 | 第3群 | かなの畳み込みの各呼び出し元の出力を固定する（半角カナ・合成濁点・ゔ・ゕゖ） | high | 済 | `de8350c` | 入力（半角カナ ｶﾞｷﾞ・合成濁点つきの か・ゔ・ゕ・ゖ）を test_helper に KANA_FOLD_SAMPLE として 1 つ置き（エスケープを書かず pack で作る）、8 つの呼び出し元に 1 件ずつ、いまの出力を固定した。WordRequestDuplicateCheck.fold は「ガギガヴヵヶ」。KanaRow は行がカ・カ・ア・カ・カ、基本字がカ・カ・ウ・カ・ケ。SearchRegexp#for_reading と WordsHelper の突き合わせは NFKC をかけないので半角カナと合成濁点が残る。SiteStatistics の 50 音の集計キーは畳んで合算。ReadingExtractor の整形は「ガギガヴ」（ゕ・ゖ を落とす）。RhythmPattern は「gagigavu」＋ゕゖ がそのまま残る。MoraCount は 6。値は rails runner で取ってから書いた。合格判定は全部通過 |
| T0-19 | 第3群 | 管理一覧のジャンル絞り込みの結果を固定する | high | 済 | このコミット | admin/words_controller_test に 1 件。独立した木（大 1・中 2・小 3）と 4 語（うち 1 語は未公開）を作り、大分類なら 4 語すべて、中分類（労働法）なら配下の小分類 2 つの 3 語、別の中分類（民法）なら 1 語、小分類（判例）なら公開・未公開の 2 語、と結果の集合ごと固定した。既存のテスト（小分類・大分類・存在しない id）はそのまま。合格判定は全部通過 |
| T0-20 | 第3群 | publish_guard と deck が削除済みの語義を数えないことを固定する（system テスト） | high | 未着手 | | |
| T0-21 | 第3群 | `JAPANESE_ORIGIN_NAME` が SeedCatalog の語種名に含まれることを確かめる | high | 未着手 | | |
| R2-01 | 第4群 | 使われていない Ruby コードを消す（SiteStatistics の 2 つの total は消さない） | high | 未着手 | | |
| R2-02 | 第4群 | 使われていないビューと i18n を消す | high | 未着手 | | |
| R2-03 | 第4群 | 使われていない JS を消す | high | 未着手 | | |
| R2-04 | 第4群 | 使われていない CSS セレクタ・効いていない宣言・未使用のトークンを消す | high | 未着手 | | |
| R2-05 | 第4群 | 設定とタスクの残骸を片付ける（robots.txt の `#` の行は対象外。`cap -T` を通す） | high | 未着手 | | |
| R2-06 | 第4群 | テストの残骸を片付ける（期待値は変えない） | high | 未着手 | | |
| R2-07 | 第4群 | CSS の無い残骸クラスをビューから消す | high | 未着手 | | |
| C3-01a | 第5群（前半） | 基準値・しきい値を持ち主に寄せる（初版の分: 別名定数・立項スコア・JAPANESE_ORIGIN_NAME・文字種の記号・横棒（同じ演算順）・レート上限・RANKING_LIMIT・ja.yml） | high | 未着手 | | |
| C3-01b | 第5群（前半） | 基準値・しきい値を持ち主に寄せる（補完監査の分: VOWELS.size・書き出しの上限・母音遷移の上限・MIN_LENGTH・ENTRY_SCORE_RANGE） | high | 未着手 | | |
| C3-02 | 第5群（前半） | 提案 payload のキーの一覧を、AnnotationProposal の定数 1 か所にまとめる | high | 未着手 | | |
| C3-03 | 第5群（前半） | 一括登録の調査 JSON の読み取りを、ResearchJson.array_at に寄せる | high | 未着手 | | |
| C3-04 | 第5群（前半） | 外部コマンドの有無の判定をクラスで 1 回に揃え、`ReadingExtractor#normalize` を公開する | high | 未着手 | | |
| C3-05 | 第5群（前半） | 認証の開放を明示する（WordRequestsController に `only:`） | high | 未着手 | | |
| C3-06 | 第5群（前半） | 管理画面の判定を `admin_page?` の 1 つにする | high | 未着手 | | |
| C3-07a | 第5群（前半） | 管理画面で重複している UI を 1 つにする（初版の分: キューの絞り込み・状態ラベル・状態タブ） | high | 未着手 | | |
| C3-07b | 第5群（前半） | 管理画面で重複している UI を 1 つにする（補完監査の分: 提案パネル・コピー欄・書き出しの欄・用語解説・下端のバー） | high | 未着手 | | |
| C3-08 | 第5群（前半） | ページネーションの計算を値オブジェクトにする | high | 未着手 | | |
| C3-09 | 第5群（前半） | 50 音表の定義を KanaRow へ移す | high | 未着手 | | |
| C3-10 | 第5群（前半） | キャッシュの書き方を正典に寄せる（TTL の定数化、ホームと About のキャッシュをモデルへ） | max | 未着手 | | |
| C3-11a | 第5群（前半） | テストのヘルパ（with_rails_cache・with_fragment_cache・with_config・with_env・CANONICAL_HOST・create_published_word）を test_helper に集める | high | 未着手 | | |
| C3-11b | 第5群（前半） | 管理画面のテストのログインを揃え、局所変数 `words` の名前と 422 の記号を揃える | high | 未着手 | | |
| D1-04 | 第5群（前半） | 派生値の一覧と直し方を、data-model §3 の 1 つの表にまとめる（C3-12 と組にする） | high | 未着手 | | |
| C3-12 | 第5群（前半） | 読み由来の派生値の組み立てを `WordSense.reading_derivations` 1 か所にし、backfill の欠陥を直す（計画書 §0.2 の例外） | max | 未着手 | | |
| E-01 | 第5群の区切り | **オーナーの作業**: merge して、本番で C3-12 版の `bin/rails backfill:verify` を流し、ring_crossing_count の不整合が 0 件であることを確かめてもらう | high | 未着手 | | |
| C3-13 | 第5群（後半） | ビューで派生値を計算し直すのをやめる（`_kana_ring` は保存列にし、NULL の表示は残す。統計の小さな再計算） | max | 未着手 | | |
| C3-14 | 第5群（後半） | 代表語義と語義の順序を `Word#primary_sense`・`ordered_senses` に定める（words/index の max_by は置き換えない） | max | 未着手 | | |
| C3-15 | 第5群（後半） | かなの畳み込みを KanaFold にまとめる | max | 未着手 | | |
| C3-16 | 第5群（後半） | 絶対 URL の組み立てを SiteUrl にまとめる（起点と裸のホストを分ける） | max | 未着手 | | |
| C3-17 | 第5群（後半） | 1 語の直列化で使う共通部品（ジャンルの区切り・ライセンス）をまとめる | max | 未着手 | | |
| C3-18 | 第5群（後半） | コントローラにある業務規則をモデルへ移す（今日の一語は `featured_on(date, count:)`） | max | 未着手 | | |
| C3-19 | 第5群（後半） | JavaScript の重複を共有モジュールにまとめる | high | 未着手 | | |
| C3-20 | 第5群（後半） | 検索スライダーと feature_range の値と文言を、ヘルパから data 値で渡す | high | 未着手 | | |
| C3-21 | 第5群（後半） | CSS の二重定義を 1 つにし、フレーム幅を `--frame-width` にする | high | 未着手 | | |
| C3-22 | 第5群（後半） | テストで公開語を作る方法を `create_published_word` に揃える（1 ファイルずつ） | high | 未着手 | | |
| C3-23 | 第5群（後半） | system テストの操作ヘルパを ApplicationSystemTestCase に集める | high | 未着手 | | |
| C3-24 | 第5群（後半） | 登録予定単語の「段」の定義を 1 か所にする（書き出しのキー "reading" は変えない） | high | 未着手 | | |
| G4-01 | 第6群 | CLAUDE.md を 200 行程度に再編する（design.md の節番号は変えない） | high | 未着手 | | |
| G4-02 | 第6群 | docs/history/ を作り、歴史と記録を隔離する | high | 未着手 | | |
| G4-03 | 第6群 | docs が現行のコードと一致しているかを最終確認する（JS の地図・CSS の配置・README の規模の数値など） | high | 未着手 | | |
| G4-04a | 第6群 | コメントを「なぜ」だけにする: app/models・app/services・app/jobs | high | 未着手 | | |
| G4-04b | 第6群 | コメントを「なぜ」だけにする: app/controllers・app/helpers・app/views（robots の `#` の行と word.svg.erb は対象外） | high | 未着手 | | |
| G4-04c | 第6群 | コメントを「なぜ」だけにする: app/javascript・app/assets | high | 未着手 | | |
| G4-04d | 第6群 | コメントを「なぜ」だけにする: lib・config | high | 未着手 | | |
| G4-04e | 第6群 | コメントを「なぜ」だけにする: test | high | 未着手 | | |
| G4-05 | 第6群 | この計画書と監査の記録を docs/history/ へ移す（T0-15 を残すかもここで決める） | high | 未着手 | | |
| F-01 | 第7群 | A04-1: 特徴の再調査の書き出しで「日本語のみ」の絞り込みが外れない不具合を直す（管理画面） | high | 未着手 | | 改修とは別の PR。merge はオーナーの指示で |
| F-02 | 第7群 | C-01: /words から「条件を変える」で /search へ移ると条件の一部が落ちる不具合を直す | high | 未着手 | | 同上 |
| F-03 | 第7群 | C-03: ログイン中だけ差分が出る HTML を public で HTTP キャッシュしている問題を直す | max | 未着手 | | 同上。キャッシュに触れるので max |
| F-04 | 第7群 | J-17: コピーボタンを 2 秒以内に 2 回押すと「コピーしました」のまま戻らない不具合を直す | high | 未着手 | | 同上 |
| F-05 | 第7群 | A05-1: 統計 §8 のリード文の「実例の下線」を、実装（淡い面のハイライト）に合わせる | high | 未着手 | | 同上 |
| F-06 | 第7群 | A10-1 の後始末: `design_tokens_test.rb` の `delta_rgb` を最大差にし、ダークの `--bg-tint` を最大差 19 以上にする | high | 未着手 | | 同上。色はリーダーが両テーマで実測して候補を出し、オーナーが選ぶ |

## 6. 受付箱（計画外で見つけたもの）

<!-- 実行中に見つけたものは、その場で直さずここに書く。段階の切れ目でまとめて判断する -->

| 日付 | 内容 | 見つけた単位 | 判断 |
|---|---|---|---|
| 2026-10-03 | `test/system/admin_annotation_console_test.rb:189`（語義を複製しても、ジャンルの大分類の「その場追加」が使える）は、単独で流すと毎回落ちる（変更前の e4bc1a7 でも同じ）。全体で流すと通ることが多いが、D1-03 の合格判定で 1 度落ちた。テストの順序か状態への依存が疑われる | D1-03 | 改修の範囲外。C3-23（system テストのヘルパの集約）で調べるか、別の PR で直す |
| 2026-10-03 | docs/overview.md §7 の「production は socket ＋ 環境変数」は、本番ではリポジトリの production 設定を使わないという事実（D1-01）と食い違う | D1-02 | G4-03（docs の最終確認）で直す |
| 2026-10-03 | `app/assets/stylesheets/components.css:4497` のコメント「押して選んだ2ノードと、そのあいだの1本」は、鎖を何拍でもつなげる現行の操作と食い違う（A05-7。計画書は A05-7 を D1-10・D1-15 に割り当てており、CSS の分が漏れている） | D1-15 | D1-16（CSS のコメント）で「選んだ鎖」に直す → D1-16b で直した |
| 2026-10-03 | 効いていない CSS の規則が 2 つある。①`annotate.css` の `.ann-sense.is-complete { border-color: var(--success) }` は、`.ann-sense` が border を持たないので見た目に出ない（「完了した語義の枠を緑にする」意図が実現していない。いまの完了表示は番号のバッジだけ）。②`annotate.css` の 767px 以下の `.ann-add__input { font-size: 16px }` は、components.css の `input[type="text"]`（特異度が高い）と同じ値の重ねで、無くても変わらない | D1-16a | ①は枠を出すと見た目が変わるので、計画書 §7.4 の扱い（出すか、規則を消すかはオーナー判断）。②は消しても見た目が変わらないので、C3 の不要な規則の整理で消せる。コメントは D1-16a で事実に合わせた |
| 2026-10-03 | main の CI（2026-10-02、PR #165 の merge `e4d2b7a`）が `test/system/admin_annotation_console_test.rb:165`（ジャンルのその場追加で既にある名前を入れると…）で 1 回落ちている（`.ann-add__msg` の文言が出る前に判定した）。同じコミットの PR 上の CI は通っている。受付箱の :189 と同じ console_test の不安定さ。デプロイは CI を待たないので本番には影響していない | D1-17a | オーナーに報告する。C3-23（system テストのヘルパの集約）か別の PR で、待ち方を直す |
| 2026-10-03 | システムテストの不安定さの原因を特定した。`system_sign_in` で fixture の管理者（パスワード "password"）がログインすると、Chrome のパスワード漏洩の警告が入力を奪い、以後ネイティブの入力（fill_in・send_keys・Actions・クリック）がページに届かなくなる（公開ページでも）。ドライバに `--disable-features=PasswordLeakDetection` と `profile.password_manager_leak_detection: false` ほかの設定を足すと届く（2026-10-03、Chrome 154.0.8037.92 で使い捨てのテストで確認）。console_test:165・:189、deck_test:84 の不安定さも、ログイン後のネイティブ入力に頼っている箇所なので、これが原因の可能性が高い（推測） | D1-17b | テストの設定の変更なので、C3-23 で直すのが筋（4 つのうちどの設定が効いているかは、そのとき切り分ける）。直したら、各テストの JS 経由の回避策と ApplicationSystemTestCase の注記を見直す。オーナーに報告する |

## 7. 作業ログ

<!-- セッションごとに 1 行。最後に追記する -->

| 日付 | 始めたときの HEAD | やったこと | 終えたときの HEAD | 止まった理由 |
|---|---|---|---|---|
| 2026-10-02 | `e4d2b7a` | 段階 0: 方針・台帳・再開コマンドを作った | `d8ce684` | 段階 1 はオーナーの回答待ち |
| 2026-10-02 | `d8ce684` | 段階 1（目的の確定）、段階 2（棚卸し B-01〜B-08、補完監査 A-01〜A-11。A-03 は見送り）。途中で 1 回利用上限に当たり、A-07 をやり直した。**`ffb0664` では A-10 がまだ実行中なのに段階 2 を「済」にしてしまった**（台帳の A-10 は未着手のままだった）ので、このコミットで A-10 を取り込んで正した | `1110261` | 段階 2 の完了。P-01 は max 推奨 |
| 2026-10-03 | `1110261` | 段階 3 の P-01（a〜d。計画書を補完監査の結果で改訂）・P-02（反証レビュー 16 件）・P-03（a: レビューの反映で 78 項目に、b: 台帳 §5 に 92 行で写した） | `e5951b5` | P-04 はオーナーの回答待ち |
| 2026-10-03 | `e5951b5` | P-04（承認「推奨通り」）、E-00、第1群（D1-01・02・03・05）と第2群（D1-06〜D1-21。D1-14・16・17 は分量のため a・b に分けた）をすべて済にした。途中で 1 回利用上限に当たり、D1-14b の途中から再開した（未コミットの差分は台帳の単位どおりに仕上げた）。システムテストの不安定さの原因（ログイン後の Chrome のパスワード漏洩の警告）と、main の CI の 1 回の失敗を受付箱に記録した | `2f5a3c7` | 第1〜2群の切れ目。merge をするか（main への merge は本番デプロイ）と、受付箱の整理をオーナーに確認する |
