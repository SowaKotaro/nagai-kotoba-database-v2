# 言語学的特徴の点検結果(word-feature-audit スキルの出力)を読み、変更の行に分ける。
# 行は「足す」か「外す」で、語義を sense_id で指す(書き出しは FeatureAuditExport)。保存はしない。
# 管理画面は行の一覧を見せてオーナーに選ばせ、選んだ行だけを FeatureAuditApplication が適用する。
# 適用の直前にもう一度読み直して検証し直すので、確認のあとに語が直されていても古い判断で書き込まない。
#
# 入力の形(キーの正はここ。スキルの文書 .claude/skills/word-feature-audit/SKILL.md はこの写し):
#   { "version": "1", "task": "linguistic_features_audit",
#     "changes": [ { "action": "add" | "remove", "word_id", "sense_id", "name", "target", "target_reading", "reason" } ] }
#   target_reading は「足す」のときだけ要る。reason は確認の画面に出すだけ。
# 種別: 調査 JSON の入出力。
class FeatureAuditImport
  ACTIONS = %w[add remove].freeze

  # 1つの変更。problem が nil の行だけを適用できる。problem は admin.feature_audits.problems の訳のキー。
  #   matches: 「外す」で消す特徴の行(該当部分が完全に一致するもの)。
  Row = Struct.new(:index, :action, :word, :sense, :linguistic_feature, :name, :target, :target_reading,
                   :reason, :problem, :matches, keyword_init: true) do
    def applicable? = problem.nil?
    def add? = action == "add"
  end

  def initialize(json_text)
    @json_text = json_text.to_s
  end

  # 行の配列。JSON が読めない・changes が無いときは nil。
  def rows
    entries = ResearchJson.array_at(@json_text, "changes")
    return nil unless entries

    senses = WordSense.where(id: entries.map { |entry| entry["sense_id"].to_i })
                      .includes(:word, word_sense_features: :linguistic_feature).index_by(&:id)
    features = LinguisticFeature.all.index_by(&:name)
    seen = []

    entries.each_with_index.map do |entry, index|
      row = build_row(entry, index, senses, features)
      key = [ row.action, row.sense&.id, row.name, row.target ]
      row.problem ||= :duplicate if seen.include?(key)
      seen << key
      row
    end
  end

  private

  def build_row(entry, index, senses, features)
    sense = senses[entry["sense_id"].to_i]
    sense = nil if sense && entry["word_id"].present? && sense.word_id != entry["word_id"].to_i
    row = Row.new(index: index, action: entry["action"].to_s, word: sense&.word, sense: sense,
                  linguistic_feature: features[entry["name"].to_s], name: entry["name"].to_s,
                  target: entry["target"].to_s, target_reading: entry["target_reading"].to_s,
                  reason: entry["reason"].to_s, matches: [])
    row.problem = problem_of(row)
    row
  end

  def problem_of(row)
    return :unknown_action unless ACTIONS.include?(row.action)
    return :sense_not_found unless row.sense
    return :unknown_feature unless row.linguistic_feature
    return :missing_target if row.target.blank?

    row.add? ? addition_problem(row) : removal_problem(row)
  end

  # 足す行は、WordSenseFeature の検証(該当部分が表層形と読みの中にある)を先に当てる。
  def addition_problem(row)
    return :missing_target_reading if row.target_reading.blank?
    return :target_not_in_surface unless row.word.surface.to_s.include?(row.target)
    return :target_reading_not_in_reading unless row.sense.reading.to_s.include?(row.target_reading)

    :already_attached if attached(row).any?
  end

  def removal_problem(row)
    row.matches = attached(row)
    :not_attached if row.matches.empty?
  end

  # 語義に付いている、同じ特徴・同じ該当部分の行。該当部分は文字どおりに比べる
  # (target の照合順序は清濁を同一視するので、DB の比較ではなく Ruby の == で見る。WordSenseFeature.matching と同じ考え)。
  def attached(row)
    row.sense.word_sense_features.select do |feature|
      feature.linguistic_feature_id == row.linguistic_feature.id && feature.target == row.target
    end
  end
end
