class RestructureWordCandidateStatuses < ActiveRecord::Migration[8.1]
  # 登録予定単語のステータスを「次に何を待っているか」で読める形に組み直す(UI の見直し)。
  #
  #   旧: 10:upload 20:expand 30:duplicate 40:notation 50:done 60:登録済み 80:要判断 85:重複 90:不要
  #   新: 10:仕分け待ち 20:拡張待ち 40:表記待ち 45:表記の確認待ち 50:登録待ち 60:登録済み 80:保留 85:重複 90:不要
  #
  # - 旧 expand は「/expand の結果待ち」と「取り込み済み・送る前」を expanded_at で分けていた。
  #   新しい流れでは取り込んだ語(元の語・集めた語)は仕分けに戻して確かめるので、後者は仕分け待ちへ移す。
  # - 旧 duplicate の段は仕分けと表記の確認に組み込んだ(照合は画面に並べるたびに行う)ので、仕分け待ちへ移す。
  # - 旧 notation も同じく結果の有無(notated_at)で分けていたので、取り込み済みの語を「表記の確認待ち」へ。
  # - expanded_at は「拡張の元にして結果を取り込んだ」印に改める。集めた語自身は拡張していないので消す。
  OLD_COMMENT = "10:upload 20:expand 30:duplicate 40:notation 50:done 60:登録済み 80:要判断 85:重複 90:不要"
  NEW_COMMENT = "10:仕分け待ち 20:拡張待ち 40:表記待ち 45:表記の確認待ち 50:登録待ち 60:登録済み 80:保留 85:重複 90:不要"
  OLD_EXPANDED_AT_COMMENT = "expand の結果を取り込んだ時刻(expand で増えた語は作成時刻)"
  NEW_EXPANDED_AT_COMMENT = "拡張の元にして /expand の結果を取り込んだ時刻(集めた語自身は NULL)"

  def up
    execute "UPDATE word_candidates SET status = 10 WHERE status = 20 AND expanded_at IS NOT NULL"
    execute "UPDATE word_candidates SET status = 10 WHERE status = 30"
    execute "UPDATE word_candidates SET status = 45 WHERE status = 40 AND notated_at IS NOT NULL"
    # 自分を元にした語を持たない「集めた語」の expanded_at を消す(DISTINCT で派生表を実体化させ、同じ表を更新できるようにする)
    execute <<~SQL.squish
      UPDATE word_candidates AS c
      LEFT JOIN (SELECT DISTINCT seed_id FROM word_candidates WHERE seed_id IS NOT NULL) AS s ON s.seed_id = c.id
      SET c.expanded_at = NULL
      WHERE c.seed_id IS NOT NULL AND s.seed_id IS NULL
    SQL
    change_column_comment :word_candidates, :status, from: OLD_COMMENT, to: NEW_COMMENT
    change_column_comment :word_candidates, :expanded_at, from: OLD_EXPANDED_AT_COMMENT, to: NEW_EXPANDED_AT_COMMENT
  end

  # 旧の段へは戻しきれない(仕分け待ちに移した語が expand・duplicate のどちらにいたかは残らない)ため、
  # 仕分け待ちは upload のまま、表記の確認待ちだけを notation へ戻す。消した expanded_at も戻らない。
  def down
    execute "UPDATE word_candidates SET status = 40 WHERE status = 45"
    change_column_comment :word_candidates, :status, from: NEW_COMMENT, to: OLD_COMMENT
    change_column_comment :word_candidates, :expanded_at, from: NEW_EXPANDED_AT_COMMENT, to: OLD_EXPANDED_AT_COMMENT
  end
end
