# /expand(word-expansion-research スキル)の出力 JSON を取り込む(拡張の画面)。
#
# 形式: { "seeds": [ { "id": 元の語の ID, "input": 元の語, "words": [集めた語...], "note": 系統・軸の要約 } ] }
# 書き出しに載せた ID で元の語を引くので、スキルが表記を変えても対応が崩れない。
#
# - 集めた語を仕分け待ちに入れる(元の語と系統の根を持たせ、仕分けの画面で元の語の系統として括って並べる)。
# - 元の語も仕分け待ちに戻し、「拡張の元にした」印(expanded_at)を立てる(系統の先頭で、ほかの語と一緒に確かめる)。
#   有望な軸が無く words が空の元の語も同じく戻す(拡張せずに進めるかを仕分けで決める)。
# - すでに入っている語(不要にした語を含む)・収録済みの語は入れない。
# - 拡張待ちにいない元の語は見送る。同じ JSON を2回貼っても増えない。
class WordCandidateExpansionImport
  Result = Struct.new(:counts, :messages, keyword_init: true)

  def initialize(json_text)
    @json_text = json_text
  end

  # JSON の形が読めないときは nil を返す(呼び出し側でエラー表示)。
  def call
    seeds = ResearchJson.array_at(@json_text, "seeds")
    return nil unless seeds

    @result = Result.new(counts: Hash.new(0), messages: [])
    WordCandidate.transaction do
      seeds.each { |entry| import_seed(entry) }
    end
    @result
  end

  private

  def import_seed(entry)
    seed = WordCandidate.find_by(id: entry["id"].to_i)
    return skip(:unknown, entry) unless seed
    return skip(:stale, entry) unless seed.expanding?

    Array(entry["words"]).each { |surface| add_word(seed, surface.to_s.strip) }
    seed.update!(status: :triage, expanded_at: Time.current, note: WordCandidate.append_note(seed.note, entry["note"]))
    @result.counts[:seeds] += 1
  end

  def add_word(seed, surface)
    return if surface.blank? || surface == seed.surface

    if WordCandidate.exists?(surface: surface)
      @result.counts[:existing] += 1
    elsif Word.exists?(surface: surface)
      @result.counts[:registered] += 1
    else
      WordCandidate.create!(surface: surface, status: :triage, **seed.expansion_attributes)
      @result.counts[:created] += 1
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    @result.counts[:errors] += 1
    @result.messages << "#{surface}: #{WordCandidate.save_error_message(e)}"
  end

  def skip(reason, entry)
    @result.counts[reason] += 1
    @result.messages << "##{entry['id']} #{entry['input']}: #{I18n.t("admin.word_candidates.import_results.#{reason}_reason")}"
  end
end
