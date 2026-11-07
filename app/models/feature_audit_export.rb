# 言語学的特徴の点検用データの書き出し。点検は、特徴の新設・判定基準の見直しのあとに、
# 公開済みの語すべてを決めた特徴の目で見直すための作業(例: 「方言」を足したあと、過去の語にも付ける)。
#
# 特徴だけの再調査の書き出し(FeatureResearchExport。特徴が1つも無い未調査の語義だけ)と違い、
# 公開済みの語を、特徴が付いていても「特徴なしで確定」していても対象にし、いま付いている特徴を添える。
# 調べる側が既にある特徴と見比べて、足すものと外すものを決めるため。語義は sense_id で指すので、
# 複数語義の語も取り違えない。意味やジャンルは載せない(FeatureResearchExport と同じ理由)。
#
# 点検の結果(word-feature-audit スキルの出力)の取り込みは FeatureAuditImport、適用は FeatureAuditApplication。
# 種別: 調査 JSON の入出力。
class FeatureAuditExport
  VERSION = "1".freeze
  TASK = "linguistic_features_audit".freeze

  # 公開済みの語を id 順に引く。点検する特徴は名前で受け、マスタに無い名前は落とす(空なら全特徴を点検する)。
  def self.target_words(limit:, from_id: nil, to_id: nil)
    scope = Word.annotated
    scope = scope.where(id: from_id..) if from_id
    scope = scope.where(id: ..to_id) if to_id
    scope.includes(word_senses: [ :word_origins, { word_sense_features: :linguistic_feature } ])
         .order(:id).limit(limit)
  end

  def initialize(words, feature_names: [])
    @words = words
    known = LinguisticFeature.pluck(:name)
    @feature_names = Array(feature_names).map(&:to_s).select { |name| known.include?(name) }.uniq
  end

  attr_reader :feature_names

  def as_json
    {
      "version" => VERSION,
      "task" => TASK,
      "features_to_check" => @feature_names,
      "words" => word_entries,
      "masters" => { "linguistic_features" => LinguisticFeature.in_glossary_order.map(&:name) }
    }
  end

  def to_json(*)
    JSON.pretty_generate(as_json)
  end

  private

  # 語義は登録順(id 順。表示の並びと同じ)。特徴は表層形の中の位置の順。
  def word_entries
    @words.map do |word|
      {
        "word_id" => word.id,
        "surface" => word.surface,
        "senses" => word.word_senses.sort_by(&:id).map { |sense| sense_entry(sense) }
      }
    end
  end

  def sense_entry(sense)
    {
      "sense_id" => sense.id,
      "reading" => sense.reading,
      "word_origins" => sense.word_origins.map(&:name),
      "linguistic_features" => sense.word_sense_features.sort_by(&:target_start).map do |feature|
        { "name" => feature.linguistic_feature.name, "target" => feature.target, "target_reading" => feature.target_reading }
      end
    }
  end
end
