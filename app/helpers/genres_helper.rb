module GenresHelper
  # ジャンル配下の公開語義数(Issue 21)。
  # 末端(小分類)は集計値そのもの、上位(大・中)は子孫の合計を再帰的に求める。
  def genre_published_count(genre, by_parent, counts)
    children = by_parent[genre.id] || []
    return counts[genre.id].to_i if children.empty?

    children.sum { |child| genre_published_count(child, by_parent, counts) }
  end

  # 一覧の1行に添える短いジャンル表記。末端(小分類)だけだと何の分野か伝わらないので、
  # 直上(中分類)と中黒で繋いで「数学・論理学」の形にする。大分類まで並べると長すぎるので出さない。
  GENRE_LINEAGE_SEPARATOR = "・".freeze

  def genre_lineage_label(genre)
    [ genre.parent&.name, genre.name ].compact.join(GENRE_LINEAGE_SEPARATOR)
  end

  # 公開語義が1件以上ある子ジャンルだけを返す(空の分類・空リンクを載せない)。
  def genres_with_published(parent_id, by_parent, counts)
    (by_parent[parent_id] || []).select { |genre| genre_published_count(genre, by_parent, counts).positive? }
  end
end
