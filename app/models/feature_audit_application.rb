# 言語学的特徴の点検結果のうち、オーナーが選んだ行を適用する(足す・外す)。行は FeatureAuditImport が作る。
#   - 適用するのは、選ばれていて、検証に通った(problem が nil の)行だけ。
#   - 注釈状態(公開・未公開)・意味・ジャンルなど、特徴のほかには触れない。
#   - 全体を1トランザクションで行い、途中で失敗したら全体を巻き戻す。
# 種別: 書き込み処理。
class FeatureAuditApplication
  # added=足した特徴の数, removed=外した特徴の行の数, words=何かを変えた語の数。
  Result = Struct.new(:added, :removed, :words, keyword_init: true)

  def initialize(rows, selected_indexes)
    @rows = Array(rows)
    @selected = Array(selected_indexes).map(&:to_i)
  end

  def apply
    added = 0
    removed = 0
    word_ids = []

    Word.transaction do
      targets.each do |row|
        if row.add?
          # create! は1行ずつ: 特徴の数は代表値として words に焼いてあり、after_commit で焼き直す(RefreshesWordMetrics)。
          row.sense.word_sense_features.create!(linguistic_feature: row.linguistic_feature,
                                                target: row.target, target_reading: row.target_reading)
          added += 1
        else
          row.matches.each(&:destroy!)
          removed += row.matches.size
        end
        word_ids << row.word.id
      end
      # 特徴の行(中間テーブル)を足し引きしても語は touch されないので、詳細ページの HTTP キャッシュ
      # (Word#cache_dependencies)が古い内容のまま 304 を返さないよう、語の updated_at を動かす(BulkDetachment と同じ)。
      # touch_all はコールバックを通らないが、動かすのは updated_at だけで、派生値には関わらない。
      Word.where(id: word_ids.uniq).touch_all if word_ids.any?
    end

    Result.new(added: added, removed: removed, words: word_ids.uniq.size)
  end

  private

  def targets
    @rows.select { |row| @selected.include?(row.index) && row.applicable? }
  end
end
