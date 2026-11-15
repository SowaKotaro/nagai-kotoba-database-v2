---
name: seo-monthly-review
description: nagai-kotoba-database-v2 の「SEO の月次の点検」。オーナーが research/inputs/seo/<YYYY-MM>/ に置いた Search Console のエクスポート(検索パフォーマンス・ページのインデックス登録・クロールの統計情報。任意で GA4)をスクリプトで集計し、本番を読み取りだけで点検し、docs/seo-operations.md の表に当てて、警報・検索の水準・入れた施策の判定・次の一手の提案を決まった形で報告し、docs/seo-log.md に 1 か月分を足す。「SEO の月次を回して」「サーチコンソールのデータを見て」「今月の SEO を見て」「/seo」と言われたときに使う。数えるのはスクリプトで、提案まで(本番の変更・採否はオーナー)。
allowed-tools: Bash(python3 script/seo_monthly.py:*), Bash(python3 script/seo_site_check.py:*), Bash(ls:*), Read, Glob, Grep, Edit
---

# SEO の月次の点検

**手順・判定の表・施策の台帳の正は `docs/seo-operations.md`**。このスキルは入口で、規則を写していない。
食い違いに気づいたら、文書のほうに従う。

## 引数

- 空(既定) … 今日の日付の月(`YYYY-MM`)を対象にする。
- `YYYY-MM` … その月を対象にする(置いてあるエクスポートのフォルダ名と同じ)。

## 進め方

1. `docs/seo-operations.md` を **最初から最後まで** Read する(§1 の決まりと §4 の判定の表は、要約せずに従う)。
2. `docs/seo-log.md` を Read する(前の月の行、表 4 の判定待ち、前の月の所見)。
3. `docs/seo-operations.md` §3 の手順を、**番号の順に、飛ばさず**進める。
   - 入力が足りなければ、§3 の 2 のとおり、足りないものを §2 の表の番号で伝えて止まる。
   - `python3 script/seo_site_check.py <月>` は本番へ約 40 件の GET を送る。1 回の月次で 1 回だけ回す(やり直しで何度も叩かない)。
4. 報告は §3 の 9 の形のまま返す(項目の順と見出しを変えない)。

## してはいけないこと

`docs/seo-operations.md` §1 が正。とくに次の 4 つ。

- CSV を自分で数え直す。`report.md`・`site-check.md` に無い数字を書く。
- 検索の水準が「戻った」でない月、または警報がある月に、新しい施策を提案する。
- `docs/seo-plan.md` §7「やらないこと」にある案を提案する。
- 本番に書き込む、コードを変える、commit する(どれもオーナーが決めてから。このスキルが書き換えるのは `docs/seo-log.md` だけ)。
