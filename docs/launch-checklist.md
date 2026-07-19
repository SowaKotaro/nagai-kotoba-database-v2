# インデックス解禁チェックリスト（Issue 43・44）

「注釈済み 300〜500 語」に達したら、このチェックリストに沿って検索エンジンへの公開（インデックス解禁）を行う。
過去データは後から取れないため、**計測（§1）だけは解禁前に完了させる**（[`growth-strategy.md`](growth-strategy.md) §3）。

## 前提（解禁判断の条件）

- [x] 注釈済みの公開語数が 300〜500 語に達している（`Word.annotated.count`）
- [ ] プライバシーポリシー `/privacy` が公開されている（Issue 42。実装済み）
- [ ] About・ライセンス表記（CC BY 4.0）・連絡先が最新である

## 1. 計測の立ち上げ（解禁前に済ませる — Issue 44）

- [ ] GA4 のプロパティを作成し、本番サーバの環境変数に `GA4_MEASUREMENT_ID`（`G-` で始まる測定ID）を設定して Puma を再起動
- [ ] 本番ページのソースに gtag タグが出ていることを確認（`curl -s https://nagai-kotoba-database.jp | grep gtag`）
- [ ] GA4 のリアルタイムレポートで自分のアクセスが計測されることを確認
- [ ] Search Console にプロパティを追加し所有権を確認（DNS 確認を推奨。使えない場合は環境変数 `GOOGLE_SITE_VERIFICATION` に検証タグの content 値を設定）
- [ ] Bing Webmaster Tools も同様に所有権を確認（`BING_SITE_VERIFICATION`。Search Console からのインポートが手軽）
- [ ] 解禁前のベースライン（直帰の状況・既存流入の有無）を1〜2週間分確認しておく

## 2. インデックス解禁（Issue 43）

- [x] 本番サーバの環境変数に `INDEXING_ENABLED=true` を設定して Puma を再起動
  （未設定 = 全ページ `noindex`。設定すると通常ページの robots メタが消え、ファセット等の個別 noindex だけが残る）
- [x] 本番で確認: トップ・単語詳細に `<meta name="robots"` が**無い**こと、`/search` には `noindex,follow` が**残る**こと

## 3. sitemap 送信（解禁と同時）

- [ ] Search Console に `https://nagai-kotoba-database.jp/sitemap.xml` を送信
- [ ] Bing Webmaster Tools にも同じ sitemap を送信
- [x] robots.txt の `Sitemap:` 行が本番ホストを指していることを確認（動的生成済み）

## 4. 観測の開始（解禁後）

- [ ] Search Console のカバレッジ（インデックス登録状況）を週次で確認
- [ ] GA4 で [`growth-strategy.md`](growth-strategy.md) §3 の KPI の観測を開始
- [ ] 流入クエリ（Search Console の検索パフォーマンス）を確認し、狙いクエリ（「◯文字の言葉」等）との差分をコンテンツ方針に反映
- [ ] 解禁日を本ファイルに記録する

## 解禁の記録

| 項目 | 値 |
|---|---|
| 解禁日 | 2026-07-19 |
| 解禁時の注釈済み語数 | 294（sitemap.xml の単語ページ数。登録語数は 300 超） |
