# 候補の語義から「その語を起点にした窓」で数件の word_id を選ぶ(Issue 86)。
#
# 単純に word_id の小さい順で N 件取ると、どの語から見ても同じ顔ぶれ(最も古い語)が並び、
# 新しく収録した語は語のページからのリンクを一度も受け取らない(2026-09-17 の実測で公開語の 43%)。
# そこで起点の語 id より大きい側から順に取り、足りなければ先頭へ回り込む。
#   - 同じ語なら何度開いても同じ結果(決定的。キャッシュしてよい)
#   - 語ごとに窓がずれるので、候補が多いグループでも全員に出番が回る
#   - 候補が N 件以下なら従来どおり全件
# 2 本とも word_id の範囲条件 + ORDER BY + LIMIT なのでインデックスが効いたまま。
module WordWindow
  # sense_scope: 候補の語義(起点の語自身は呼び出し側で除いておく)
  # pivot_id:    起点の語 id
  def self.word_ids(sense_scope, pivot_id:, limit:)
    after = pick(sense_scope.where(word_id: (pivot_id + 1)..), limit)
    return after if after.size >= limit

    after + pick(sense_scope.where(word_id: ...pivot_id), limit - after.size)
  end

  def self.pick(scope, limit)
    scope.order(:word_id).distinct.limit(limit).pluck(:word_id)
  end
  private_class_method :pick
end
