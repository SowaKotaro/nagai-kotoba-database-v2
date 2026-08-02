# アノテーション調査でスキルに渡すマスタ一覧(選択肢)。まとめての書き出し
# (AnnotationResearchExport)と1語の再調査(ReannotationExport)で同じ形を渡すため共通化する。
# スキル側は「ここにある名前と一字一句同じ表記」で提案を書く約束なので、形を分岐させない。
class AnnotationMasters
  def self.as_json
    new.as_json
  end

  def as_json
    {
      "genres" => genre_tree,
      "entity_types" => EntityType.order(:name).pluck(:name),
      "parts_of_speech" => PartOfSpeech.order(:name).pluck(:name),
      "word_origins" => WordOrigin.order(:name).pluck(:name),
      "linguistic_features" => LinguisticFeature.order(:name).pluck(:name)
    }
  end

  private

  # ジャンルは {大分類 => {中分類 => [小分類, ...]}} の木で渡す。提案は木にある小分類を
  # 選ぶか、既存の中分類の下に新しい小分類を提案する(大・中はスキル側で新設させない)。
  # パスの一覧だと親の名前をパスごとに繰り返してトークンを浪費するため、各名前が
  # 1回だけ現れる入れ子にする。小分類がまだ無い中分類も空配列で必ず含める
  # (無いとスキルが「寄せ先」を知らず、中分類ごと創作してしまう)。
  # 読み込み済みのハッシュから親を引く(件数分の親クエリを出さない)。
  def genre_tree
    genres = Genre.all.index_by(&:id)
    tree = {}
    genres.values.select(&:medium?).sort_by(&:name).each do |medium|
      (tree[genres[medium.parent_id].name] ||= {})[medium.name] = []
    end
    genres.values.select(&:small?).sort_by(&:name).each do |small|
      medium = genres[small.parent_id]
      tree[genres[medium.parent_id].name][medium.name] << small.name
    end
    tree.sort.to_h
  end
end
