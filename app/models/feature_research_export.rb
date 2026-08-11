# 言語的特徴だけを対象にした再調査用データの書き出し(Issue 76)。
#
# 公開済みの語のうち特徴が付いていないものを、表層形・読み・語種だけ添えて書き出す。
# 意味やジャンルは載せない。特徴の判定に要るのは「表記と読みの対応」であって語の意味ではなく、
# 余計な情報を渡すと調査が他の項目に散るため。
#
# 出力を調査に掛けて返ってくる提案 JSON は、取り込み画面(Admin::AnnotationProposalsController#new)に
# そのまま貼れる。ProposalApplication は各項目を「提案にあれば適用」で組み立てるので、
# linguistic_features しか持たない提案を反映しても、意味・ジャンル・品詞などは書き換わらない。
class FeatureResearchExport
  VERSION = "1".freeze

  # 対象語義を引く。既定は「日本語(和語・漢語)を含む語」に絞る。
  # 連濁・熟字訓・促音化といった現象は和語・漢語で起きるもので、本番実データでも
  # 日本語を含まない語の特徴付与率は 1% しかなかった(日本語を含む語は 21%)。
  def self.target_senses(limit:, japanese_only: true, from_id: nil, to_id: nil)
    scope = WordSense.features_unreviewed
    scope = scope.with_japanese_origin if japanese_only
    scope = scope.where("words.id >= ?", from_id) if from_id
    scope = scope.where("words.id <= ?", to_id) if to_id
    scope.includes(:word, :word_origins).order("words.id").limit(limit)
  end

  def initialize(senses)
    @senses = senses
  end

  def as_json
    {
      "version" => VERSION,
      "task" => "linguistic_features_only",
      "senses" => sense_entries,
      "masters" => { "linguistic_features" => LinguisticFeature.order(:id).pluck(:name) }
    }
  end

  def to_json(*)
    JSON.pretty_generate(as_json)
  end

  private

  def sense_entries
    @senses.map do |sense|
      {
        "word_id" => sense.word_id,
        "sense_id" => sense.id,
        "surface" => sense.word.surface,
        "reading" => sense.reading,
        "word_origins" => sense.word_origins.map(&:name)
      }
    end
  end
end
