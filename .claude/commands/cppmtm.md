---
description: commit → push → PR 作成 → main へ merge までを一気に実行（cppmtm）
argument-hint: "[任意: コミット/PR に含める補足指示]"
---

作業中の変更について **commit → push → PR 作成 → main への merge** までを一気に実行してください
（cppmtm = commit, push, pr, merge to main の頭文字）。都度の確認は不要。

- 引数（あれば考慮する）: $ARGUMENTS

手順:

1. **コミット前チェックを全部通す**。CLAUDE.md の強制チェックと同じ内容:
   ```bash
   bundle exec rubocop
   bundle exec brakeman --no-pager
   bundle exec bundler-audit check --update
   bin/importmap audit
   bin/rails test test:system
   ```
   システムテストは WSL 環境用の実行方法（メモリ `system-tests-wsl-chrome` 参照:
   `LD_LIBRARY_PATH` + `CHROME_BIN` 指定）で実行すること。
   指摘・失敗が残ったままコミットしない。
2. **ブランチ**: main にいる場合は `feature/<内容>` ブランチを切る（Issue/PR 番号は入れない）。
   既に feature ブランチで作業中ならそのまま使う。main に直接コミットしない。
3. **コミット → push → PR 作成**:
   - コミットメッセージは日本語。
   - `git push -u origin <ブランチ>` → `gh pr create`（タイトル・本文も日本語。
     本文に実行したチェックの結果を書く）。
4. **CI を待って merge**: `gh pr checks <番号> --watch` で CI 通過を確認してから
   `gh pr merge <番号> --merge --delete-branch`。その後ローカル main を pull して最新化する。

注意:
- 今回の作業と**無関係な未コミット変更は巻き込まない**。ステージから除外し、その旨を報告する。
- CI が落ちた場合は merge せず、原因を修正して push し直してから再度 CI を待つ。
