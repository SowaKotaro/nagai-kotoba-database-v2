# アノテーション調査用データの書き出し(Issue 38)。
# 対象語(word_id・表層形・読み)とマスタ一覧(ジャンル木・エンティティ・品詞・語種・
# 言語学的特徴)をまとめた JSON を作る。この JSON を word-annotation-research スキルへ
# 渡すと、語ごとの提案 JSON(取り込み画面に貼る形式)が返ってくる。
class AnnotationResearchExport
  VERSION = "1".freeze

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

  # ジャンルは中分類・小分類までのパスの一覧で渡す。提案は小分類パスから選ぶか、
  # 既存の中分類の下に新しい小分類を提案する(大・中はスキル側で新設させない)。
  def masters
    {
      "genres" => genre_paths,
      "entity_types" => EntityType.order(:name).pluck(:name),
      "parts_of_speech" => PartOfSpeech.order(:name).pluck(:name),
      "word_origins" => WordOrigin.order(:name).pluck(:name),
      "linguistic_features" => LinguisticFeature.order(:name).pluck(:name)
    }
  end

  # 大分類は中分類パスの先頭に必ず現れるので、単独では渡さない。
  # ソートすると親(中分類)が子(小分類)より先に並ぶ。
  def genre_paths
    genres = Genre.all.index_by(&:id)
    genres.values.reject(&:large?).map { |genre| path_names(genre, genres) }.sort
  end

  # 読み込み済みのハッシュから祖先を辿る(語数分の親クエリを出さない)。
  def path_names(genre, genres)
    chain = [ genre ]
    chain.unshift(genres[chain.first.parent_id]) while chain.first.parent_id
    chain.map(&:name)
  end
end
