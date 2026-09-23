# 登録予定単語の upload(前処理の1段目)。箇条書きテキストを upload の語として入れるフォームオブジェクト。
#
# 既に入っている語(不要にした語を含む)は作り直さず、どの状態にいたかを件数で返す
# (表層形のユニーク制約が「一度見た語」の集合を兼ねるため)。
# 収録済みの語も入れる(expand の元にする使い方があるため。重複は duplicate の段で見つかる)。
class WordCandidateIntake
  include ActiveModel::Model

  # 一度に貼れる行数の上限(/notation の入力の実績が 400 行超のため、余裕を見た値)。
  MAX_LINES = 1000

  # 集計結果。created=新しく入れた数, existing={状態=>件数}, errors=入れられなかった行。
  Result = Struct.new(:created, :existing, :errors, keyword_init: true)

  attr_accessor :text

  def surfaces
    @surfaces ||= text.to_s.each_line.filter_map do |raw|
      raw.strip.sub(BulkWordRegistration::BULLET, "").strip.presence
    end.uniq
  end

  def too_many?
    surfaces.size > MAX_LINES
  end

  def call
    result = Result.new(created: 0, existing: Hash.new(0), errors: [])
    surfaces.each { |surface| intake_one(surface, result) }
    result
  end

  private

  # 1語ずつ独立に入れる(1行の失敗で他の行を巻き戻さない。BulkWordRegistration と同じ作法)。
  # 既存の判定は DB に任せる(照合順序 as_ci で、ひらがな⇔カタカナ違いも同じ語として扱う)。
  def intake_one(surface, result)
    if (existing = WordCandidate.find_by(surface: surface))
      result.existing[existing.status] += 1
    else
      WordCandidate.create!(surface: surface, status: :upload)
      result.created += 1
    end
  rescue ActiveRecord::RecordInvalid => e
    result.errors << "#{surface}: #{e.record.errors.full_messages.join('、')}"
  rescue ActiveRecord::RecordNotUnique
    # 先頭 191 字(prefix index)が既存の語と同じ長い語。極めて稀なので行のエラーとして返す。
    result.errors << "#{surface}: #{I18n.t('admin.word_candidates.intake.not_unique')}"
  end
end
