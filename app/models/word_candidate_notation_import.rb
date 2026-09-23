# /notation(word-notation-research スキル)の出力 JSON を取り込む(notation の段)。
#
# 形式: { "words": [ { "id": ID, "input": 元の表記, "surface": 統一後の表記, "entry_score": 1〜5,
#                      "confidence": "high|medium|low", "note": 注記, "split": [分割後の語...](任意) } ] }
#
# - 表記を置き換えて「取り込み済み」(notated_at)を立てる。段を done へ送るのは画面の最後のボタン。
# - 立項スコアが DOUBTFUL_ENTRY_SCORE 以下の語は「要判断」へ
#   (スキルが「立項に疑義がある語」として上部リストから外した語。捨てずにオーナーが判断する)。
# - 置き換え後の表記が収録済みの語・別表記・ほかの登録予定単語と重なったら「重複」へ
#   (重複確認は表記を統一する前に済ませているため、統一で新たに重なった語をここで拾う)。
#   表層形は置き換えず、統一後の表記はメモに残す。
# - split(連結に疑義がある語の分割案)があれば、元の語は「不要」にし、分割後の語を duplicate の段に入れる
#   (分割後の語はまだ重複確認も表記統一もしていないため、duplicate からやり直す)。
# - notation の段にいない語・取り込み済みの語は見送る。同じ JSON を2回貼っても二重に動かない。
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
    @check = WordCandidateDuplicateCheck.new
    WordCandidate.transaction do
      words.each { |entry| import_word(entry) }
    end
    @result
  end

  private

  def import_word(entry)
    candidate = WordCandidate.find_by(id: entry["id"].to_i)
    return skip(:unknown, entry) unless candidate
    return skip(:stale, entry) unless candidate.notation? && candidate.notated_at.nil?

    split = Array(entry["split"]).map { |surface| surface.to_s.strip }.compact_blank
    return split_word(candidate, split, entry) if split.size >= 2

    normalize_word(candidate, entry)
  end

  def normalize_word(candidate, entry)
    surface = entry["surface"].to_s.strip.presence || candidate.surface
    attributes = { entry_score: entry_score(entry), confidence: confidence(entry), notated_at: Time.current,
                   note: WordCandidate.append_note(candidate.note, entry["note"]) }

    matches = @check.matches_for(surface, except: candidate)
    if matches.any?
      note = I18n.t("admin.word_candidates.import_results.duplicate_note", surface: surface, other: matches.first.surface)
      candidate.update!(attributes.merge(status: :duplicated, note: WordCandidate.append_note(attributes[:note], note)))
      @result.counts[:duplicate] += 1
    else
      doubtful = attributes[:entry_score] && attributes[:entry_score] <= WordCandidate::DOUBTFUL_ENTRY_SCORE
      candidate.update!(attributes.merge(surface: surface, status: doubtful ? :pending : :notation))
      @check.register(candidate)
      @result.counts[doubtful ? :held : :normalized] += 1
      @result.counts[:renamed] += 1 if candidate.saved_change_to_surface?
    end
  end

  def split_word(candidate, surfaces, entry)
    surfaces.each do |surface|
      if WordCandidate.exists?(surface: surface) || Word.exists?(surface: surface)
        @result.counts[:existing] += 1
      else
        @check.register(WordCandidate.create!(surface: surface, status: :duplicate, **candidate.expansion_attributes))
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
