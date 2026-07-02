module SearchesHelper
  # ジャンルを 大 > 中 > 小 の階層順に、深さ分だけ字下げした select 用の選択肢を返す。
  # どの階層を選んでも配下の小分類で絞り込めるよう、全階層を選択肢に含める。
  # 全ジャンルを1クエリで読み、メモリ上で木を組み立てる(N+1 を避ける)。
  def hierarchical_genre_options
    genres_by_parent = Genre.order(:level, :name).group_by(&:parent_id)
    genre_option_rows(genres_by_parent, nil, 0)
  end

  private

  def genre_option_rows(genres_by_parent, parent_id, depth)
    Array(genres_by_parent[parent_id]).flat_map do |genre|
      [ [ "#{'　' * depth}#{genre.name}", genre.id ] ] +
        genre_option_rows(genres_by_parent, genre.id, depth + 1)
    end
  end
end
