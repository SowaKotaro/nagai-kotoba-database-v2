# インデックス解禁チェックリスト（Issue 43・44）

**解禁は 2026-07-19 に実施済み**（下記「解禁の記録」）。以降、本書は
**(a) 当時何をやったかの記録** と **(b) まだ残っている作業** の two-in-one として使う。
チェックの `[–]` は「やらないと決めたもの」。
再び同じ作業が要るのは、**別ドメインへ移るとき**か**ステージング環境を公開するとき**。

> 過去データは後から取れないため、**計測（§1）だけは解禁前に立ち上げる**という原則は
> 次回も同じ（[`growth-strategy.md`](growth-strategy.md) §3）。

## 前提（解禁判断の条件）

- [x] 注釈済みの公開語数が 300〜500 語に達している（`Word.annotated.count`）
- [x] プライバシーポリシー `/privacy` が公開されている（Issue 42）
- [x] About・ライセンス表記（CC BY 4.0）・連絡先が最新である

## 1. 計測の立ち上げ（解禁前に済ませる — Issue 44）

- [x] GA4 のプロパティを作成し、本番サーバの環境変数に `GA4_MEASUREMENT_ID`（`G-` で始まる測定ID）を設定して Puma を再起動
- [x] 本番ページのソースに gtag タグが出ていることを確認（`curl -s https://nagai-kotoba-database.jp | grep gtag`）
- [x] GA4 のリアルタイムレポートで自分のアクセスが計測されることを確認
- [x] Search Console にプロパティを追加し所有権を確認（DNS 確認を推奨。使えない場合は環境変数 `GOOGLE_SITE_VERIFICATION` に検証タグの content 値を設定）
- [–] ~~Bing Webmaster Tools の所有権確認~~ … **当面やらない**（2026-09-16 オーナー判断）。やるなら `BING_SITE_VERIFICATION` の ENV は実装済みで、Search Console からのインポートが手軽
- [x] 解禁前のベースライン（直帰の状況・既存流入の有無）を確認しておく

## 2. インデックス解禁（Issue 43）

- [x] 本番サーバの環境変数に `INDEXING_ENABLED=true` を設定して Puma を再起動
  （未設定 = 全ページ `noindex`。設定すると通常ページの robots メタが消え、ファセット等の個別 noindex だけが残る）
- [x] 本番で確認: トップ・単語詳細に `<meta name="robots"` が**無い**こと、`/search` には `noindex,follow` が**残る**こと

## 3. sitemap 送信（解禁と同時）

- [x] Search Console に `https://nagai-kotoba-database.jp/sitemap.xml` を送信
- [–] ~~Bing Webmaster Tools にも同じ sitemap を送信~~ … **当面やらない**（上と同じ判断）
- [x] robots.txt の `Sitemap:` 行が本番ホストを指していることを確認（動的生成済み）

## 4. 観測の開始（解禁後 — ここから先は継続作業）

- [ ] Search Console のカバレッジ（インデックス登録状況）を週次で確認
      — 解禁後に 2 度、クロール事故を検知して是正している（Issue 80・81）。この週次確認が検知手段
- [ ] GA4 で [`growth-strategy.md`](growth-strategy.md) §3 の KPI の観測を開始
- [ ] 流入クエリ（Search Console の検索パフォーマンス）を確認し、狙いクエリ（「◯文字の言葉」等）との差分をコンテンツ方針に反映

## 解禁の記録

| 項目 | 値 |
|---|---|
| 解禁日 | 2026-07-19 |
| 解禁時の注釈済み語数 | 294（sitemap.xml の単語ページ数。登録語数は 300 超） |
| 解禁時に設定した環境変数 | `INDEXING_ENABLED=true` / `GA4_MEASUREMENT_ID`（本番 Puma の systemd override.conf） |

### 解禁後に起きたこと（次に同じ手順を踏む人へ）

- **2026-07-28**: Search Console のインデックス除外レポート（noindex 309・robots ブロック 47 ほか）を受けて
  クロール導線を整理（Issue 74）。**内部リンクの約6割がインデックス不可 URL を指していた**。
- **2026-08-20**: 表示回数が約半減。原因は**シャッフルのリンクが毎回新しい URL を生んでいたこと**
  （noindex 除外 3,186）。生成元を絶ち、面の棚卸しを行った（Issue 80）。
- **2026-08-25**: canonical の二重エスケープ・実在しないマスタ id で面が無限に湧く問題などを是正（Issue 81）。

いずれも**解禁してから初めて見える**類の問題だった。解禁直後の数週間は
Search Console を週次で見ること。
