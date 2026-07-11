# アノテーション調査用データの書き出し(Issue 38)。
# 対象語(word_id・表層形・読み)とマスタ一覧(ジャンル木・エンティティ・品詞・語種・
# 言語学的特徴)をまとめた JSON を作る。この JSON を word-annotation-research スキルへ
# 渡すと、語ごとの提案 JSON(取り込み画面に貼る形式)が返ってくる。
class AnnotationResearchExport
  VERSION = "2".freeze

  def initialize(words)
    @words = words
  end

  def as_json
    {
      "version" => VERSION,
      "words" => word_entries,
      "masters" => masters
    }
  end

  def to_json(*)
    JSON.pretty_generate(as_json)
  end

  private

  def word_entries
    @words.map do |word|
      {
        "word_id" => word.id,
        "surface" => word.surface,
        "reading" => word.word_senses.map(&:reading).uniq.join("、")
      }
    end
  end

  # ジャンルは {大分類 => {中分類 => [小分類, ...]}} の木で渡す。提案は木にある小分類を
  # 選ぶか、既存の中分類の下に新しい小分類を提案する(大・中はスキル側で新設させない)。
  def masters
    {
      "genres" => genre_tree,
      "entity_types" => EntityType.order(:name).pluck(:name),
      "parts_of_speech" => PartOfSpeech.order(:name).pluck(:name),
      "word_origins" => WordOrigin.order(:name).pluck(:name),
      "linguistic_features" => LinguisticFeature.order(:name).pluck(:name)
    }
  end

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
