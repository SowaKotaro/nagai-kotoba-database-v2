---
description: SEO の月次の点検（Search Console のエクスポートを集計し、本番を点検して、次の一手を報告する。seo-monthly-review スキル）
argument-hint: "[任意: 対象の月 YYYY-MM。既定は今月]"
---

`seo-monthly-review` スキルを**明示的に**使って、SEO の月次の点検を実行してください。

- 引数: $ARGUMENTS（空なら今月。`YYYY-MM` ならその月）
- 入力: `research/inputs/seo/<月>/`（オーナーが置いた Search Console のエクスポート。置き方は `docs/seo-operations.md` §2）
- 出力: `research/outputs/seo/<月>/report.md`・`site-check.md`、`docs/seo-log.md` への追記、決まった形の報告
- `docs/seo-operations.md` の手順（§3）と判定の表（§4）に厳密に従うこと。**数えるのはスクリプト**で、エクスポートに無い数字は書かない。
- 提案まで。本番の変更・コードの変更・commit は、オーナーが決めてから。

まず Skill ツールで `seo-monthly-review` を起動してください。
