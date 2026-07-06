# ジャンル階層のハブページ(Issue 21)。誰でも閲覧できる。
# 大→中→小のツリーを、各分類の公開語義数つきで単語一覧の絞り込みへリンクする。
class GenresController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    # 隣接リストを1回で読み、親IDでまとめる(SearchesController と同じ形)。
    @genres_by_parent = Genre.order(:name).group_by(&:parent_id)
    # 公開(注釈済み)の語義数を末端(小分類)ごとに集計。上位は子の合計で導出する。
    @published_counts = WordSense.published.group(:genre_id).count
  end
end
