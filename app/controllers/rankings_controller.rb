# 公開ランキング(/rankings)。読みの長さだけでなく、拍数・字面・小書きのかな・濁点など
# さまざまな観点の上位を1ページに並べる。各枠の「もっと見る」は同じ並びの単語一覧へ渡す。
class RankingsController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    # 順位表として成立しない枠(該当語が少なく全員が載ってしまう枠)は丸ごと出さない。
    @boards = WordRanking.all.filter_map do |ranking|
      rows = ranking.board
      [ ranking, rows ] if rows.any?
    end
  end
end
