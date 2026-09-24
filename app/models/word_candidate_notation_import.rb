# /notation(word-notation-research スキル)の出力 JSON を取り込む(表記の画面)。
#
# 形式: { "words": [ { "id": ID, "input": 元の表記, "surface": 統一後の表記, "entry_score": 1〜5,
#                      "confidence": "high|medium|low", "note": 注記, "split": [分割後の語...](任意) } ] }
#
# - 表記を置き換え、立項スコア・確からしさ・注記を持たせて「表記の確認待ち」にする。
#   立項スコアが低い語・統一後に収録済みの語などと重なる語も、ここでは振り分けない
#   (確認の画面で、保留・除外を最初から選んだ状態で並べ、オーナーが見てから確定する)。
# - 統一後の表記が、ほかの登録予定単語とまったく同じ表記になった語だけは重複にする
#   (表層形は一意なので置き換えられない。同じ語が2つ入っていたということ)。
# - split(連結に疑義がある語の分割案)があれば、元の語は「不要」にし、分割後の語を仕分け待ちに入れる
#   (分割後の語はまだ誰も判断していないため、仕分けからやり直す)。
# - 表記待ちにいない語は見送る。同じ JSON を2回貼っても二重に動かない。
# - 入れられない語(長すぎる表記・分割後の語など)は、その語だけを表記待ちに残して行のエラーにする。
class WordCandidateNotationImport
  Result = Struct.new(:counts, :messages, keyword_init: true)

  def initialize(json_text)
    @json_text = json_text
  end

  # JSON の形が読めないときは nil を返す(呼び出し側でエラー表示)。
  def call
    words = ResearchJson.array_at(@json_text, "words")
    return nil unless words

    @result = Result.new(counts: Hash.new(0), messages: [])
    WordCandidate.transaction do
      words.each { |entry| import_word(entry) }
    end
    @result
  end

  private

  def import_word(entry)
    candidate = WordCandidate.find_by(id: entry["id"].to_i)
    return skip(:unknown, entry) unless candidate
    return skip(:stale, entry) unless candidate.notating?

    split = Array(entry["split"]).map { |surface| surface.to_s.strip }.compact_blank
    apply_entry(entry) { split.size >= 2 ? split_word(candidate, split, entry) : normalize_word(candidate, entry) }
  end

  # 1語ぶんを savepoint で囲んで当てる。入れられない語(長すぎる表記など)は、その語の変更と件数だけを戻して
  # 行のエラーにし、ほかの語は取り込む(スキルの出力の1語の不備で、取り込み全体を止めないため)。
  def apply_entry(entry)
    counts = @result.counts.dup
    WordCandidate.transaction(requires_new: true) { yield }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    @result.counts = counts
    @result.counts[:errors] += 1
    @result.messages << "##{entry['id']} #{entry['input']}: #{WordCandidate.save_error_message(e)}"
  end

  def normalize_word(candidate, entry)
    surface = entry["surface"].to_s.strip.presence || candidate.surface
    attributes = { entry_score: entry_score(entry), confidence: confidence(entry), notated_at: Time.current,
                   note: WordCandidate.append_note(candidate.note, entry["note"]) }

    if surface != candidate.surface && WordCandidate.where.not(id: candidate.id).exists?(surface: surface)
      note = I18n.t("admin.word_candidates.import_results.collided_note", surface: surface)
      candidate.update!(attributes.merge(status: :duplicated, note: WordCandidate.append_note(attributes[:note], note)))
      @result.counts[:collided] += 1
    else
      candidate.update!(attributes.merge(surface: surface, status: :notated))
      @result.counts[:notated] += 1
      @result.counts[:renamed] += 1 if candidate.saved_change_to_surface?
      @result.counts[:doubtful] += 1 if candidate.doubtful_entry?
    end
  end

  def split_word(candidate, surfaces, entry)
    surfaces.each do |surface|
      if WordCandidate.exists?(surface: surface) || Word.exists?(surface: surface)
        @result.counts[:existing] += 1
      else
        WordCandidate.create!(surface: surface, status: :triage, **candidate.expansion_attributes)
        @result.counts[:created] += 1
      end
    end
    note = I18n.t("admin.word_candidates.import_results.split_note", surfaces: surfaces.join(" / "))
    candidate.update!(status: :rejected, notated_at: Time.current, note: WordCandidate.append_note(candidate.note, [ note, entry["note"] ].compact.join(" ")))
    @result.counts[:split] += 1
  end

  def entry_score(entry)
    score = Integer(entry["entry_score"], exception: false)
    score if score&.between?(1, 5)
  end

  def confidence(entry)
    entry["confidence"].to_s.presence_in(WordCandidate::CONFIDENCES)
  end

  def skip(reason, entry)
    @result.counts[reason] += 1
    @result.messages << "##{entry['id']} #{entry['input']}: #{I18n.t("admin.word_candidates.import_results.#{reason}_reason")}"
  end
end
