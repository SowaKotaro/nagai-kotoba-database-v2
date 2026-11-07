---
name: word-feature-audit
description: nagai-kotoba-database-v2 の公開済みの語すべてを、指定した言語学的特徴の目で点検し直すオフライン調査。特徴を新設したとき(例「方言」)や判定基準を見直したとき(例 数字の特殊読み)に、管理画面「言語学的特徴の点検」の書き出し(公開済みの語・語義・いま付いている特徴)を保存した research/inputs/features.json を読み、足す特徴と外す特徴の変更リストを research/outputs/features.json に書き出す。「特徴を点検して」「過去の語にも方言を付けて」「/features」と言われたときに使う。新しい語の注釈は word-annotation-research、1語のやり直しは word-reannotation-research。
---

# 言語学的特徴の点検（オフライン）

特徴の**新設**や**判定基準の見直し**のあとで、公開済みの語すべてを決めた特徴の目で見直すための調査。
結果は「足す」「外す」の変更リストで、管理画面「言語学的特徴の点検」（`/admin/feature_audit`）に貼ると、
オーナーが 1 行ずつ確かめて、選んだ行だけを適用する。提案キュー（annotation_proposals）は通らない。

新しい語の注釈は `word-annotation-research`（`/annotation`）、1 語のやり直しは `word-reannotation-research`
（`/reannotation`）。**取り違えないこと。**

## 判断基準は既存の細則が正

**始める前に必ず [`../word-annotation-research/linguistic-features.md`](../word-annotation-research/linguistic-features.md)
を Read する。** 特徴ごとの付ける条件・付けない条件・`target` の切り方・ゴママヨ系の逆引きはすべてあちらが正で、
ここには写さない。対応表は [`../word-annotation-research/SKILL.md`](../word-annotation-research/SKILL.md) の手順8。
特徴の定義は [`config/linguistic_features_glossary.yml`](../../../config/linguistic_features_glossary.yml)。

## 入力

`$ARGUMENTS` がファイルパスならそのファイル、空なら `research/inputs/features.json`。どちらも無ければその場で聞く
（DB や公開 API から勝手に語を集めない）。中身は管理画面の書き出し（`FeatureAuditExport`）で、形は次のとおり:

```json
{
  "version": "1",
  "task": "linguistic_features_audit",
  "features_to_check": ["方言"],
  "words": [
    { "word_id": 12, "surface": "ダウンタウンのガキの使いやあらへんで!",
      "senses": [ { "sense_id": 34, "reading": "ダウンタウンノガキノツカイヤアラヘンデ",
                    "word_origins": ["日本語", "英語"],
                    "linguistic_features": [ { "name": "連濁", "target": "…", "target_reading": "…" } ] } ] }
  ],
  "masters": { "linguistic_features": ["連濁", "…", "方言"] }
}
```

- **`features_to_check` に挙がった特徴だけを点検する。** 空の配列なら全特徴を点検する（重いので、オーナーが
  明示したときだけ）。挙がっていない特徴は、明らかな誤りに気づいても変更に入れず、最後の報告で触れるだけにする。
- `linguistic_features` は**いま付いている特徴**。足す前に、同じ特徴・同じ該当部分が既に無いか見比べる。
- 語義は `sense_id` で指す。複数語義の語は語義ごとに読みが違うことがあるので、`target_reading` はその語義の
  `reading` から切り出す。

## 手順

1. **細則を読む**（上の「判断基準」）。点検する特徴の節（例: 方言は §3.16、特殊読みは §3.12）と、§1 の切り方、
   §4 の表層形の手がかりを確かめる。
2. **ふるい分け（1 周目）**: 全語を、§4 の手がかり・読みと表層形の突き合わせで流し見て、点検する特徴が
   付きそうな語（候補）と、いま付いている点検対象の特徴（見直す行）を拾う。語数が多いので、ここは
   1 語ずつ検索しない。候補の拾い漏れを減らすため、手がかりに当たらなくても**表層形を 1 語ずつ目で読む**。
3. **判定（2 周目）**: 候補と見直す行だけを、細則に照らして 1 件ずつ判定する。根拠が要るもの（方言の地域、
   作品固有の読み、語源）は WebSearch で裏取りする（細則「出典の信頼度」）。迷うものは変更に入れず、
   最後の報告に「保留」として挙げる（でっち上げない）。
4. **変更を書き出す**（下の「出力」）。`target` は表層形の連続した部分文字列、`target_reading` はその語義の読みの
   連続した部分文字列をそのまま切り出す（字種も含めて。読みに中黒や記号は無い）。
5. **自己点検**: 書き出したファイルを読み直し、`target` が表層形に、`target_reading` が読みに含まれているか、
   足す行が既に付いていないか、外す行が実際に付いているか（`linguistic_features` と完全に一致するか）を確かめる。
   スクリプトで確かめてよい。
6. **報告**（チャット）: 足す・外すの件数、特徴ごとの内訳、保留にした語と理由、点検対象外で気づいたこと。

入力が数百語を超えるときは、ふるい分けは全体で行い、判定は 20〜30 件ずつ進める（取りこぼしを減らすため）。

## 出力

`research/outputs/features.json` に、**次の形の JSON だけ**を書き出す（上書き。説明文は入れない）。
キーの正は `app/models/feature_audit_import.rb`（このスキルの記述はその写し）。

```json
{
  "version": "1",
  "task": "linguistic_features_audit",
  "changes": [
    { "action": "add", "word_id": 12, "sense_id": 34, "name": "方言",
      "target": "あらへん", "target_reading": "アラヘン", "reason": "関西方言の打ち消し（〜へん）" },
    { "action": "remove", "word_id": 56, "sense_id": 78, "name": "特殊読み",
      "target": "24", "reason": "アラビア数字の英語読みは字が本来とり得る読み（細則 §3.12 の 2）" }
  ]
}
```

- `action` は `add`（足す）か `remove`（外す）。`name` はマスタにある名前を一字一句そのまま書く。
- `remove` は、いま付いている特徴と `name`・`target` が完全に一致する行を外す（`target_reading` は要らない）。
  該当部分を狭める（`No.1` を `No.` に）ときは、古い該当部分の `remove` と新しい該当部分の `add` を並べる。
- `reason` は確認の画面に出るだけだが、オーナーが判断できるよう 1 行で根拠を書く（地域・基準の節など）。
- 変更が 1 件も無ければ `"changes": []` を書き、報告で「変更なし」と言う。
- 同じ変更を 2 度書かない（2 行目は確認の画面で「重複」として選べなくなる）。

## 適用の流れ（オーナー向けのメモ）

1. 管理画面「調査データ」→「言語学的特徴の点検」で、点検する特徴を選んで書き出し、`research/inputs/features.json` に保存する
   （JSON ファイルとして保存するリンクがある）。
2. Claude Code で `/features` を実行する。
3. 返ってきた `research/outputs/features.json` を同じ画面の「点検結果の取り込み」に貼り、行を確かめて適用する。
