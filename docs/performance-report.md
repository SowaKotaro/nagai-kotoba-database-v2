# パフォーマンス調査レポート（2026-08-06〜07）

データ量が増えてきて速度低下が気になる、という所感を起点に、**一般公開ページと管理者ページの
ボトルネックを実測**し、そのうち対処できたものを実装した記録。
「何が遅かったか」「なぜ遅かったか」「何をしたか」「まだ残っているか」を後から追えるようにまとめる。

- 対象ブランチ: `feature/performance-tuning`
- 実装した対処: マイグレーション1本（ランキング指標の非正規化）+ キャッシュ3系統

---

## 1. 計測方法

推測を混ぜないため、**実際のリクエストを流して**計測した。

| 何を | どうやって |
| --- | --- |
| ページごとの所要時間 | `ActionDispatch::Integration::Session` で実ページを叩き、各5回の中央値を採る |
| SQL の本数・時間 | `sql.active_record` を購読して集計（AR のクエリキャッシュは `uncached` で無効化） |
| ビュー描画の内訳 | `render_template` / `render_partial` / `render_collection` を購読し、パーシャル単位で集計 |
| クエリの実行計画 | MySQL の `EXPLAIN ANALYZE`（実行回数 `loops=` が見えるので相関サブクエリの検出に有効） |
| データ増加時の伸び方 | 開発DBを **別スキーマ `nagai_kotoba_bench` に10倍複製**して同じ計測を再実行 |

計測に使った条件:

- 開発DBの実データ **1,760語 / 1,762語義 / 1,131ジャンル**（うち公開 1,683語）
- 10倍データ **17,600語 / 17,620語義 / 1,131ジャンル**（うち公開 16,830語）
  … ジャンルは増やしていない。「語だけが増えたときにどうなるか」を見るため
- キャッシュは `null_store`（開発既定 = 冷）と `memory_store`（本番相当 = 温）の両方

> **注意**: 10倍データは開発DBの複製なので、表層形にだけ連番を足して重複を避けている。
> 分布は実データと同じ。数値はこの WSL 環境のもので、本番VPSの絶対値とは異なる。

計測スクリプトは `tmp/` に置いた（`tmp/` は git 管理外）。再計測したくなったら:

```bash
MULTIPLIER=10 bin/rails runner tmp/scale_bench.rb   # 10倍複製を作って SQL 単位で計測
bin/rails runner tmp/bench10x.rb                    # 10倍データでページ単位に計測
WARM=1 bin/rails runner tmp/bench10x.rb             # 本番相当（memory_store）で
bin/rails runner tmp/contention_bench.rb            # アノテーション保存とクローラの競合を再現
DROP=1 bin/rails runner tmp/scale_bench.rb          # 複製スキーマを片付ける
```

---

## 2. 結論：ボトルネックは性質の違う3種類だった

| | 内容 | データ増で悪化するか | 対処 |
| --- | --- | --- | --- |
| **A** | 相関サブクエリの ORDER BY / 全件集計 | **する（ほぼ完全な線形）** | ✅ 対処済み |
| **B** | ジャンル1,131件・100行を1件1パーシャルで描画 | しない（が既に最重） | ⬜ 未対処 |
| **C** | Puma 1プロセス + プロセス内キャッシュ | 増幅要因 | ⚠️ 一部対処 + 要判断 |

**体感の主因は C だった。** 個々のリクエストが遅いのではなく、CPU を数秒握るリクエストが
プロセス全体を止めていた（詳細は §5）。

---

## 3. A：データ量に比例して重くなっていたもの

### 3.1 計測値（10倍にしたときの伸び方 / SQL 時間）

| 処理 | 1,760語 | 17,600語 | 倍率 |
| --- | ---: | ---: | ---: |
| 一覧 `sort=kana_asc` | 7.2ms | **55.7ms** | 7.7× |
| 一覧 `sort=length_desc` | 5.8ms | **47.0ms** | 8.1× |
| 一覧 `sort=dakuten_desc` | 8.4ms | **73.5ms** | 8.8× |
| 一覧 `sort=ring_crossing_asc` | 9.8ms | **88.5ms** | 9.0× |
| キーワード絞込 COUNT | 6.2ms | **54.9ms** | 8.9× |
| キーワード絞込 本体 | 14.3ms | **82.9ms** | 5.8× |
| WordRanking 全12枠 | 108ms | **828ms** | 7.7× |
| SiteStatistics 全集計 | 142ms | **777ms** | 5.5× |
| browse（50音索引） | 7.0ms | **75.2ms** | 10.7× |
| sitemap 用 pluck | 7.7ms | **80.9ms** | 10.5× |
| 一覧 `sort=created_desc`（既定） | 2.6ms | 1.8ms | 1.0× ← 唯一インデックスが効いていた |
| 単語詳細 | 22.1ms | 27.9ms | 1.3× |
| 管理 単語一覧 1ページ目 | 5.6ms | 5.6ms | 1.0× |

### 3.2 原因：`WordSort` の相関サブクエリ ORDER BY

一覧の並び替えとランキングの指標は、すべて `ORDER BY` の中で語義への相関サブクエリを
評価していた。

```sql
ORDER BY (SELECT MAX(word_senses.reading_length) FROM word_senses
          WHERE word_senses.word_id = words.id) DESC, words.id ASC
LIMIT 100
```

`EXPLAIN ANALYZE` を採ると、**`LIMIT 100` なのにサブクエリが公開語の数だけ実行され、
そのうえ filesort まで通っている**ことが分かる。

```
-> Sort: (select #2) DESC, words.id, limit input to 100 row(s) per chunk
    -> Table scan on words (rows=1760)
-> Select #2 (subquery in projection; dependent)
    -> Aggregate: max(...)  (actual time=0.004..0.004 rows=1 loops=1687)   ← 公開語の数だけ実行
```

インデックスが一切効かないので、語数にそのまま比例する。同じ式が

- 単語一覧の並び替え（既定の「収録順」以外すべて）
- `/rankings` の12枠
- **トップページの「最長ランキング」（しかもキャッシュなし）**

で使われていた。「既定の一覧は速いのに、並び替えた瞬間に遅くなる」のはこれが理由。

### 3.3 対処：指標を `words` のカラムへ落として降順複合インデックスを張る

マイグレーション `20260806100000_add_sense_metrics_to_words.rb`。

追加したカラム（すべて語義から導出した代表値）:

| 用途 | カラム |
| --- | --- |
| 件数（NOT NULL・既定0） | `sense_count` / `variant_count` / `feature_count` |
| 読みの長さ | `min_reading_length` / `max_reading_length` |
| 拍・音の特徴 | `max_mora_count` / `max_small_kana_count` / `max_chouon_count` / `max_dakuten_count` |
| 円環交差 | `min_ring_crossing_count` / `max_ring_crossing_count` |
| 五十音順の代表読み | `min_reading` / `max_reading` / `min_reversed_reading` |
| 表層形由来（STORED 生成カラム） | `surface_length` / `reading_density` |

**設計上のポイント**（試行錯誤の結果なので、変えるときは同じ検証をすること）:

1. **単純インデックスでは効かない。降順複合インデックスが要る。**
   `ORDER BY 指標 DESC, id ASC` は、`(指標)` の索引を逆走査しても `id` が DESC になって
   一致しない。`(指標 DESC, id ASC)` を明示的に張ると索引走査だけで解ける。

   | インデックス | 実行計画 | 時間 |
   | --- | --- | ---: |
   | 無し | Table scan 17,600行 + filesort | 9.26ms |
   | `(max_reading_length)` | Table scan 17,600行 + filesort（**使われない**） | 9.27ms |
   | `(max_reading_length DESC, id ASC)` | Index scan **110行** | **1.11ms** |

2. **文字列の prefix インデックスは ORDER BY に使えない。**
   `min_reading(191)` のような prefix 索引では filesort に落ちる（18.9ms）。
   全長インデックスを張れる **`VARCHAR(255)`（utf8mb4 で 1020 バイト）** に収めた。
   収録基準上の読みは最長でも数十字（実データの最長は53字）なので、実際に切り詰められることはない。

3. **`surface_length` / `reading_density` は STORED 生成カラム**にして Ruby から持たない。
   生成式にマルチバイト文字を含めると `schema.rb` のダンプが壊れる既知の制限があるため、
   式が ASCII だけで書けるこの2つに限っている（`CLAUDE.md` の「生成カラム」参照）。

4. **代表値の焼き直しは `WordSenseMetrics` が1文の UPDATE で行う。**
   `word_senses` / `word_sense_variants` / `word_sense_features` の `after_commit`
   （`RefreshesWordMetrics`）から呼ばれる。**`updated_at` は意図的に進めない** ——
   代表値は表示内容を変えないので、進めると詳細ページの ETag と llms-full のキャッシュが
   無意味に失効する。
   既存行はマイグレーションの中で埋め切っている（rake 待ちにするとデプロイ直後の
   ランキングが空になるため）。ズレたときの修復は `bin/rails backfill:sense_metrics`。

**引き換えに払ったコスト**: `words` にインデックスが16本増えた。書き込みのたびに16本の
保守が走るが、`words` は1万件規模で書き込みは登録とアノテーションだけなので許容した。
実測でもアノテーション保存は 143ms → 131ms で悪化していない。

### 3.4 結果（10倍データ / SQL 時間）

| 処理 | 対処前 | 対処後 |
| --- | ---: | ---: |
| 一覧 `sort=kana_asc` | 55.7ms | **2.9ms** |
| 一覧 `sort=length_desc` | 47.0ms | **2.1ms** |
| 一覧 `sort=dakuten_desc` | 73.5ms | **2.1ms** |
| 一覧 `sort=ring_crossing_asc` | 88.5ms | **1.9ms** |
| WordRanking 全12枠 | 828ms | **32.8ms** |

並び替えは**データ量に依存しなくなった**（索引走査で 110行しか読まない）。

---

## 4. B：ジャンル数・行数に比例する描画コスト（未対処）

SQL はほぼゼロで、時間はすべて ERB のパーシャル描画に消えている。
**データが増えても悪化しないが、現時点で公開・管理それぞれの最重ページ**。

### 4.1 `/search`（詳細検索フォーム）— 197ms、うち SQL 3.1ms

```
168.7ms  app/views/searches/_genre_filter.html.erb        1回
 98.8ms  app/views/searches/_genre_chip.html.erb       1131回   ← ジャンル1件ごとに render
  6.0ms  app/views/searches/_check_chips.html.erb         4回
```

`_genre_filter.html.erb` がジャンル1,131件それぞれに `render "genre_chip"` を呼んでいる。
1パーシャル描画あたり約0.09ms × 1,131回。

### 4.2 `/admin/tags/genres` — 228ms、うち SQL 5.3ms

`app/views/admin/tags/show.html.erb` が

- 1,131行それぞれに `button_to`（**行ごとに `<form>` を1つ生成**）
- `options_for_select` で 1,131件の `<option>` を**2つの select に**

ページネーションが無いので全件描画になる。

### 4.3 `/admin/words` — 114ms、うち SQL 7.2ms

- `admin_genre_filter_options` が 1,131個の `<option>` を生成
- 100行 × （`trash` + `pencil` アイコン）= **212回のパーシャル描画**

### 4.4 `icon` ヘルパーが毎回 `render`

`icons_helper.rb` は `render "shared/icons/#{name}"`。一覧ページで `arrow_right` だけで
102回（6.4ms）、管理一覧で200回（12.5ms）。1つ1つは軽いが行数に比例して積み上がる。

---

## 5. C：構成上の増幅要因 —— 「保存して次へ」が1〜3秒かかっていた正体

### 5.1 サーバ処理そのものは速かった

アノテーション「保存して次へ」の1往復を実測すると **143ms**（PATCH 56ms + 次の語の GET 87ms）。
体感の1〜3秒とは2桁違う。つまり**アノテーション画面自体は遅くなかった**。

### 5.2 犯人：全件出力が GIL を握り、その間サイト全体が止まる

Puma は `WEB_CONCURRENCY` 既定 **1プロセス・5スレッド**（`config/puma.rb`）。
MRI には GIL があるので、CPU バウンドな1リクエストが**5スレッド全部を止める**。

| エンドポイント | 10倍データでの所要時間 | 内訳 |
| --- | ---: | --- |
| `/llms-full.txt` | **6,027ms** | SQL は 221ms だけ。残りはテキスト組み立て |
| `/sitemap.xml` | **1,419ms** | SQL は 27ms だけ。残りは Builder の XML 組み立て |
| `/stats` | 878ms | 集計34本 |

そして**この2つには、アノテーション作業と噛み合う最悪の設計上の欠陥があった**。

- `/sitemap.xml` … **サーバ側キャッシュが無い**。`expires_in 1.day` は HTTP ヘッダを
  付けるだけなので、クローラが来るたびに再生成していた。
- `/llms-full.txt` … `Rails.cache` に載せてはいたが、キーが
  `"#{公開語数}-#{words.updated_at の最大}"`。`word_senses` は `touch: true` なので、
  **語を1つアノテーション保存するたびにキーが変わって失効**していた。

Cloudflare で AIボットを全面許可しているため、クローラ・AIエージェントの取得は常時ある。
結果として

> アノテーションを1語保存する → 直後にボットが `/llms-full.txt` を取りに来る
> → 数秒 CPU を握られる → 管理者の「次の語」がその時間だけ待たされる

という**自分で自分を詰まらせるループ**が回っていた。散発的に1〜3秒かかる、という症状と一致する。

### 5.3 対処

**指紋（版）を日単位に畳み、条件付きGET を足した**（`PublishedWordsDigest`）。

```ruby
# 版 = 公開語の最終更新日（その日の始まり）
def published_words_version
  @published_words_version ||= Word.annotated.maximum(:updated_at)&.in_time_zone&.beginning_of_day
end
```

- **収録語数を版に混ぜてはいけない。** アノテーション保存は「未公開の語を公開する」操作なので
  公開語数が必ず1増える。件数を含めると日単位に畳んでも保存のたびに版が変わり、意味が無くなる
  （実装途中に実際に踏んで、実測で気づいた）。
- 両エンドポイントとも元々 `Cache-Control: public, max-age=86400` を宣言している出力なので、
  **最大1日の遅れは元々の契約どおり**で、公開側の鮮度を新たに損ねてはいない。
- あわせて `stale?` による 304 と、`race_condition_ttl`（キャッシュ・スタンピード対策）を追加。
  `/stats` にも `race_condition_ttl` を入れた。

### 5.4 結果：競合シナリオの再現（10倍データ・本番相当キャッシュ）

```
① クローラが初回に取りに来る（キャッシュ生成）
  GET /sitemap.xml                    1637.6 ms
  GET /llms-full.txt                  6074.3 ms

② 1語目を保存 → その日の版が変わるので、次の取得で1回だけ作り直す
  PATCH /admin/annotations/:id            73.6 ms
  GET /sitemap.xml                        15.6 ms
  GET /llms-full.txt                      18.8 ms

③ 2語目を保存 → 同じ日なので版は動かない（ここが本題）
  PATCH /admin/annotations/:id            59.2 ms
  GET /sitemap.xml                        15.0 ms
  GET /llms-full.txt                      46.3 ms
  GET /llms-full.txt（If-None-Match つき） 10.3 ms  [304]

④ 3語目を保存 → 以降も作り直さない
  GET /sitemap.xml                        10.6 ms
  GET /llms-full.txt                      15.7 ms
```

アノテーション中のクローラ取得が **1.5〜6秒 → 10〜46ms**。作り直しは**1日1回**に減った。

### 5.5 まだ残っている構成上の論点（要判断・インフラ変更）

以下は影響が大きいので実装していない。オーナー判断が要る。

1. **`WEB_CONCURRENCY` を 2 以上にする**
   1リクエストの CPU が全体を止める状況そのものを緩和できる。
   ただし `config.cache_store = :memory_store` はプロセス内キャッシュなので、
   ワーカーを増やすとキャッシュが分断される（統計・ランキング・全文がワーカー数だけ作られる）。
   増やすなら Solid Cache（DB）への移行とセットで考えるべき。メモリ消費も増える。
2. **`/sitemap.xml` と `/llms-full.txt` を日次で静的ファイルとして生成する**
   rake タスク + cron で `public/` に書き出せば Puma を一切通さなくなり、
   1日1回の再生成すら request path から消える。運用の可動部が増える。
3. **`:memory_store` はデプロイのたびに全部消える。** 統計・ランキング・全文の
   キャッシュが再構築されるまで、最初のアクセスが重い。

---

## 6. 実装した対処のまとめ

| # | 対処 | 主なファイル |
| --- | --- | --- |
| 1 | ランキング指標を `words` へ非正規化（16カラム + 16索引 + バックフィル） | `db/migrate/20260806100000_add_sense_metrics_to_words.rb` |
| 2 | 代表値の再計算（1文の UPDATE） | `app/models/word_sense_metrics.rb` |
| 3 | 語義・別表記・特徴の変更に追従させる | `app/models/concerns/refreshes_word_metrics.rb` |
| 4 | `WordSort` / `WordRanking` を新カラムへ切り替え（`HAVING` を廃して `WHERE` に） | `app/models/word_sort.rb` / `word_ranking.rb` |
| 5 | 全件出力の版を日単位に畳み、条件付きGET を追加 | `app/controllers/concerns/published_words_digest.rb` |
| 6 | `/sitemap.xml` に本文キャッシュを追加（従来ゼロ） | `app/controllers/sitemaps_controller.rb` |
| 7 | `/llms-full.txt` のキャッシュキーを是正 | `app/controllers/llms_controller.rb` |
| 8 | `/browse` `/genres` の集計をキャッシュ（1時間） | `app/models/published_sense_counts.rb` |
| 9 | 重い集計にスタンピード対策 | `app/models/site_statistics.rb` |
| 10 | 修復用 rake タスク | `lib/tasks/backfill.rake`（`backfill:sense_metrics`） |

テスト: `test/models/word_sense_metrics_test.rb`（11本）/ `test/models/published_sense_counts_test.rb`（4本）/
sitemap・llms の条件付きGET テスト（5本）を追加。既存849本 + システム34本すべて green。

---

## 7. 最終計測（10倍データ = 17,600語・本番相当キャッシュ）

| ページ | 対処前 | 対処後 | |
| --- | ---: | ---: | --- |
| `/llms-full.txt` | 5,763ms | **22.9ms** | ✅ |
| `/sitemap.xml` | 1,394ms | **11.8ms** | ✅ |
| `/rankings` | 853ms | **22.5ms** | ✅ |
| `/stats` | 842ms | **49.6ms** | ✅ |
| トップ | 94.5ms | **23.3ms** | ✅ |
| `/browse`（50音索引） | 92.0ms | **16.4ms** | ✅ |
| 一覧 `sort=dakuten_desc` | 123.6ms | **54.5ms** | ✅ |
| 一覧 `sort=kana_asc` | 118.8ms | **57.3ms** | ✅ |
| `/genres` | 117.5ms | **81.7ms** | ✅ |
| 管理 単語一覧 | 129.5ms | **113.0ms** | △ |
| 単語一覧（既定） | 52.6ms | 57.2ms | － |
| 単語詳細 | 50.6ms | 49.5ms | － |
| アノテーション（1語） | 33.4ms | 37.1ms | － |
| **一覧 キーワード検索** | 155.3ms | **172.5ms** | ⬜ 未対処 |
| **`/search`（詳細検索フォーム）** | 185.8ms | **198.7ms** | ⬜ 未対処（描画コスト） |
| **`/admin/tags/genres`** | 216.4ms | **222.6ms** | ⬜ 未対処（描画コスト） |
| 一覧 深いページ（OFFSET 9900） | 114.8ms | 93.7ms | ⬜ 未対処 |
| 一覧 `sort=shuffle` | 77.1ms | 90.9ms | ⬜ 対処不能（MD5 順は設計上の全件走査） |

---

## 7.5 追記（2026-08-11）: 重複チェックの Levenshtein 総当たり（Issue 52）

公開の収録リクエスト（Issue 75）で「重複チェック」が不特定多数から叩けるようになったため、
Issue 52 の総当たりを計測して対処した。**Issue 52 に書かれていた対処法は効かないことが判明した**ので、
方針ごと差し替えている。

### 7.5.1 計測（クエリ10語 = フォームの行数上限。読みは実データを1文字ずらしたもの）

| コーパス | 対処前 | 対処後 |
|---|---|---|
| 1,000語（現在の本番 ≒ 966語） | 240 ms | **67 ms** |
| 5,000語 | 1,124 ms | **337 ms** |
| 10,000語（想定規模） | 2,250 ms | **676 ms** |
| 30,000語 | 6,770 ms | **2,026 ms** |

計測スクリプトは `tmp/dup_bench.rb`（tmp は git 管理外なので、必要なら本節の手順で作り直す）。

### 7.5.2 Issue 52 の「`reading_length` で DB 側事前絞り込み」が効かない理由

**それは `Levenshtein.far_apart?` が Ruby 側で既にやっている枝刈りと同じもの**だから。
SQL に移しても配列走査が減るだけで、コストの本体である距離計算は1件も減らない。
実データでの帯の残存率は次のとおりで、そもそも絞れていない。

| クエリの読み | 長さ帯 | 帯に残る割合 |
|---|---|---|
| 10字 | 8〜12 | 48.7% |
| 12字 | 10〜15 | **97.4%** |
| 13字 | 11〜16 | 81.6% |

収録語は「読み10文字以上」だけを集めているため**読みの長さが一箇所に固まっており、
長さによる枝刈りは原理的に効きにくい**。これは収録基準そのものに由来する性質で、
インデックスを足しても変わらない。

### 7.5.3 実際の原因と対処

コストの内訳を 100,000 回あたりで実測したところ、次のとおりだった。

| 処理 | 実測 |
|---|---|
| `String#chars`（2文字列ぶん） | 420 ms |
| `bag_distance`（文字多重集合の下界。試作） | 906 ms |
| `[a.length, b.length].max` | 11 ms |

対処は3点（いずれも `app/models/levenshtein.rb`）。

1. **帯状化 + 早期打ち切り（`#distance_within`）** — しきい値 0.8 なら許容距離は13字でも2しかない。
   対角から max より離れたセルは通らないので帯の中だけ埋める（Ukkonen）。
   行の最小値は行が進んでも下がらないため、行全体が max を超えたら打ち切る。
2. **`String#chars` をループ外へ（`*_chars` 版）** — 総当たりでは分割自体が支配的コスト（1組4µs）。
   コーパス側は1回の判定で分割を使い回す（`WordRequestDuplicateCheck#split_corpus`、
   `BulkWordRegistration#existing_readings`）。
3. **行配列の使い回し** — 行ごとの `Array.new` をやめ、2本を入れ替える。

**採用しなかったもの**: 文字多重集合による下界（bag distance）。編集距離の正しい下界だが、
Hash の確保に9µs掛かり、帯状化済みの DP より高くつく（1,047ms → 1,087ms と悪化）ため撤去した。

### 7.5.4 副産物：しきい値ちょうどの組を取りこぼしていたバグ

`far_apart?` が `(1 - threshold) * longest` を直接比較していたため、
**`(1 - 0.8)` が倍精度で `0.19999999999999996` になり、類似度がちょうど 0.8 の組を誤って弾いていた**。
読み10字・文字数差2 がこれに当たる。収録語は読み10文字以上ばかりなので、
本番の重複チェックで実際に取りこぼしが起きていた。許容距離を `ceil` で緩めに取り
（`#max_distance_for`）、最終判定は従来どおりの浮動小数比較に委ねることで解消した。

正しさは、素朴な DP を基準にしたランダム総当たり（80万組）で確認済み。
境界（しきい値ちょうど）と `far_apart?` の誤枝刈りは `test/models/levenshtein_test.rb` に回帰テストを置いた。

## 7.6 追記（2026-08-11）: `/search` のジャンルフィルタ描画（§4.1 の対処）

§4.1 で挙げた「1,131件のチップ描画」を対処した。計測は `tmp/search_bench.rb`
（`ActiveSupport::Notifications` でテンプレート単位の内訳を取る）。

| | 対処前 | 対処後 |
|---|---|---|
| `/search` 全体 | 235 ms | **34 ms**（キャッシュヒット）/ **94 ms**（ミス） |
| `_genre_filter`（内訳） | 192 ms | **4.5 ms** |

対処は2点。

1. **フラグメントキャッシュ** — 中身は「ジャンルマスタの状態」と「選択中のジャンル」だけで
   決まるので、その2つを鍵にする。
   `cache [ :search_genre_filter, Genre.all.cache_key_with_version, selected.sort ]`。
   条件なしで開く大多数の閲覧が同じ1本を引く。§4.1 の当初案にあった
   「選択状態を Stimulus で復元」は**不要**だった。選択集合を鍵に含めれば、
   状態を含んだままキャッシュできる。並び順の違いで別エントリにならないよう `sort` する。
2. **`render partial:, collection:`** — 小分類の並びをコレクション描画に変更。
   キャッシュミス側（235ms → 94ms）に効く。

**無効化**: `cache_key_with_version` が件数と最終更新時刻を1クエリで取るため、
マスタの改名・追加・削除がそのまま鍵に乗る。

**テスト**: テスト環境は `perform_caching = false` なので、素のコントローラテストでは
「キャッシュに載せたせいで壊れる」バグを検出できない。
`test/controllers/searches_genre_filter_cache_test.rb` でキャッシュを明示的に有効化し、
選択状態の混線・改名/追加/削除による無効化を固定している。

---

## 8. 残っている課題（優先順）

1. ~~**`/search` のジャンルフィルタ描画（199ms）**~~ — **対処済み（2026-08-11）。§7.6 参照。**
2. **`/admin/tags/genres`（223ms）** — ページネーション、`button_to` の1フォーム集約。
3. **一覧の絞り込みが同じ重い条件を2回流す** — `words_controller.rb#load_paginated_words` が
   `scope.count`（総ページ数用）と本体で2回。10倍のキーワード検索で COUNT 55ms + 本体 83ms。
   `LIMIT+1` で「次ページの有無」だけ見るか、条件をキーに COUNT をキャッシュする。
   総ページ数表示の UI 変更を伴う。
4. **キーワード検索の `LIKE '%...%'`** — 前方ワイルドカードでインデックス不可。
   MySQL の ngram FULLTEXT を検討する余地はあるが、現状55msなので優先度は低い。
5. **`icon` ヘルパーの `render` → 定数 SVG 文字列** — 行数の多いページで効く。
6. **`admin/annotations_controller.rb#set_navigation` の全 id pluck** — 未対応語の全 id を
   毎回メモリに読む（16,830件で12.3ms）。今は問題にならないが O(N)。
7. **深いページの OFFSET** — keyset ページネーションにしないと解けない（URL 設計の変更を伴う）。
8. **§5.5 の構成上の論点**（Puma のワーカー数 / 静的生成 / キャッシュストア）。

---

## 9. 開発時のメモ

**ローカルで `/stats`・`/rankings`・`/llms-full.txt` が遅いのは、開発環境のキャッシュが
無効（`:null_store`）だから。** `config/environments/development.rb` は
`tmp/caching-dev.txt` が無いとキャッシュを一切効かせない。

```bash
bin/rails dev:cache   # 本番相当（memory_store）に切り替わる
```

実測差（10倍データ）: `/stats` 878ms → 50ms、`/rankings` 57ms → 23ms、
`/llms-full.txt` 6,027ms → 23ms。
「本番より開発の方が遅い」ときは、まずこれを疑う。
