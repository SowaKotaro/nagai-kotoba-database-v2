# 調査の自動実行の 1 回ぶん(run)。種語を /expand → /notation → /reading と通し、段の間でふるいをかけて、
# 一括登録に貼る register.txt(step1)と reading.json(step2)を作る。段を動かすのは ResearchPipeline。
#
# 入出力は run のディレクトリに段ごとに置き、上書きしない(途中で止まっても、どこまで進んだかと何を落としたかが残る):
#   state.json            段・失敗の回数・種語・生き残っている語
#   01-expand/ 02-notation/ 03-reading/   各段の input.txt(スキルに渡す)と、スキルが書く JSON(OUTPUT_FILES)と人が読む txt
#   rejected.tsv          却下した語(段・表層形・読み・理由)。台帳(ResearchLedger)にも同じ行を足す
#   summary.md            段ごとの件数と却下の内訳(人が読む版)
#   register.txt / reading.json   最後まで残った語(人が一括登録に貼る)
#
# ふるいは「確実なものを流し、ほかは却下する」(オーナー判断。最後はアノテーションで人が目を通す)。
# 2026-11-14 に緩めた: 拡張の段は読みの文字数で落とさない(MeCab も通さない)、表記の段は確信度 medium まで・
# 立項スコア 4 以上を通す、重複は読みがほぼ同じ語だけ(ResearchDuplicateFilter)。読みの段は確信度 high のまま。
# 落ちた語は research/auto/rejected.html で見て、人が拾い直す。しきい値は各概念の持ち主の定数を引く。
# 種別: 調査 JSON の入出力。
class ResearchRun
  STAGES = %w[expand notation reading].freeze
  DONE = "done"
  ABORTED = "aborted"
  STAGE_DIRECTORIES = { "expand" => "01-expand", "notation" => "02-notation", "reading" => "03-reading" }.freeze
  # スキルが出力先のディレクトリに書く JSON の名前(既定の research/outputs/ と同じ名前)。
  OUTPUT_FILES = { "expand" => "expansion.json", "notation" => "notation.json", "reading" => "reading.json" }.freeze
  # 同じ段でこの回数だけ失敗したら(利用上限で途中終了した・出力が壊れていた)、run を止める。
  MAX_ATTEMPTS = 3

  attr_reader :directory

  # 種語は台帳に「使った」と記録する(次の run で同じ種語を取り出さないように)。
  def self.create(root, seeds:, corpus_fetched_at:, ledger:)
    directory = new_directory(root)
    run = new(directory, {
      "created_on" => Date.current.iso8601, "corpus_fetched_at" => corpus_fetched_at&.iso8601,
      "stage" => STAGES.first, "attempts" => 0, "next_id" => seeds.size + 1,
      "seeds" => seeds.each_with_index.map { |surface, index| { "id" => index + 1, "surface" => surface } },
      "words" => [], "report" => []
    })
    run.save
    ledger.append(seeds.map { |surface| run.ledger_row("used", { "surface" => surface }, nil, kind: "seed") })
    run
  end

  # root の下に、起動の日時を名前にした新しいディレクトリを作る(同じ秒に重なったら連番を足す。名前の順 = 古い順)。
  def self.new_directory(root)
    base = Pathname(root).join(Time.current.strftime("%Y%m%d-%H%M%S"))
    directory = (1..).lazy.map { |n| n == 1 ? base : Pathname("#{base}-#{n}") }.find { |path| !path.exist? }
    FileUtils.mkdir_p(directory)
    directory
  end

  def self.load(directory)
    new(Pathname(directory), JSON.parse(Pathname(directory).join("state.json").read))
  end

  # root の下の run(古い順)。
  def self.all(root)
    Pathname(root).glob("*/state.json").sort.map { |path| load(path.dirname) }
  end

  def initialize(directory, state)
    @directory = directory
    @state = state
  end

  def id = directory.basename.to_s
  def stage = @state["stage"]
  def created_on = Date.parse(@state["created_on"])
  def attempts = @state["attempts"]
  def finished? = [ DONE, ABORTED ].include?(stage)
  def seeds = @state["seeds"]
  def words = @state["words"]

  def input_path = stage_directory.join("input.txt")
  def output_path = stage_directory.join(OUTPUT_FILES.fetch(stage))

  # 今の段のスキルに渡す入力を書く。/expand・/notation は「#ID 表層形」、/reading は表層形だけ
  # (一括登録 step2 が表層形で突き合わせるため。WordCandidateExport と同じ形)。
  def write_input
    FileUtils.mkdir_p(stage_directory)
    lines = case stage
    when "expand" then seeds.map { |seed| "##{seed["id"]} #{seed["surface"]}" }
    when "notation" then words.map { |word| "##{word["id"]} #{word["surface"]}" }
    when "reading" then words.map { |word| word["surface"] }
    end
    input_path.write(lines.join("\n") + "\n")
  end

  # スキルの出力を読み、ふるいをかけて次の段へ進める。出力が読めない・入力の語が欠けていれば false
  # (段は進めない。失敗を数えるのは呼び出し側の record_failure)。known は重複照合の相手([表層形, 読み]。公開済みの語の写しと台帳)。
  def absorb(output_text, known:, ledger:)
    entries = parse_output(output_text)
    return false unless entries

    filter = ResearchDuplicateFilter.new(known)
    passed, rejected = case stage
    when "expand" then sift_expand(entries, filter)
    when "notation" then sift_notation(entries, filter)
    when "reading" then sift_reading(entries, filter)
    end
    record_stage(passed, rejected, ledger)
    true
  end

  # 段の失敗を数える。MAX_ATTEMPTS に届いたら run を止める。
  def record_failure
    @state["attempts"] += 1
    @state["stage"] = ABORTED if attempts >= MAX_ATTEMPTS
    save
    false
  end

  def save
    directory.join("state.json").write(JSON.pretty_generate(@state) + "\n")
    directory.join("summary.md").write(summary)
  end

  def ledger_row(outcome, word, reason, kind: "word")
    ResearchLedger::Row.new(recorded_on: Date.current.iso8601, run_id: id, kind:, outcome:, stage: kind == "seed" ? nil : stage,
                            surface: word["surface"], reading: word["reading"], reason:)
  end

  private

  # --- 段ごとのふるい(passed は次の段へ渡す語、rejected は [語, 理由]) ---

  # 種語ごとの系統。確信度が high でない系統は丸ごと落とす。候補は読みの文字数と重複でふるう。
  def sift_expand(entries, filter)
    candidates = entries.flat_map do |entry|
      seed = seeds.find { |s| s["id"] == entry["id"].to_i }
      Array(entry["candidates"]).select { |c| c.is_a?(Hash) && c["surface"].present? }.map do |candidate|
        { "surface" => candidate["surface"].to_s.strip, "reading" => candidate["reading"].to_s.strip.presence,
          "seed" => seed["surface"], "confidence" => entry["confidence"] }
      end
    end

    # 読みの文字数ではここで落とさない(/expand が数えて 10 字未満を除いている。オーナー判断)。読みは正規化だけする
    sift(candidates, filter) do |candidate|
      confidence = candidate.delete("confidence")
      candidate["reading"] = ReadingLengthCheck.normalize(candidate["reading"])
      next "系統の確信度が high でない(#{confidence || "なし"})" unless high?(confidence)

      candidate["id"] = next_id
      nil
    end
  end

  # 表記を確定した語。立項スコアが懸念の帯(AnnotationProposal::ENTRY_CONCERN_MAX_SCORE 以下)でなく、
  # 確信度が low でなく、分割案が無い語を通す。
  def sift_notation(entries, filter)
    by_id = entries.index_by { |entry| entry["id"].to_i }
    sift(words, filter) do |word|
      entry = by_id.fetch(word["id"])
      word["surface"] = entry["surface"].to_s.strip.presence || word["surface"]
      next "分割案あり(#{Array(entry["split"]).join(" / ")})" if Array(entry["split"]).any?
      next "立項スコアが低い(#{entry["entry_score"].inspect})" unless entry_score_enough?(entry["entry_score"])
      next "確信度が low(#{entry["confidence"] || "なし"})" unless medium_or_high?(entry["confidence"])

      nil
    end
  end

  # 読みを確定した語。確信度が high で、読みが揺れず、確定した読みで数え直しても基準に届く語だけを通す。
  def sift_reading(entries, filter)
    by_input = entries.index_by { |entry| entry["input"].to_s.strip }
    mecab = ReadingExtractor.call(words.map { |word| word["surface"] })
    sift(words, filter) do |word, index|
      entry = by_input.fetch(word["surface"])
      check = ReadingLengthCheck.call(entry["reading"], mecab[index])
      word["reading"] = check.reading
      word["research"] = entry
      next "確信度が high でない(#{entry["confidence"] || "なし"})" unless high?(entry["confidence"])
      next "読みが揺れる(#{Array(entry["alternatives"]).map { |alt| alt.is_a?(Hash) ? alt["reading"] : alt }.join(" / ")})" if Array(entry["alternatives"]).any?
      next "読みが基準に届かない(#{reading_length_label(check)})" unless check.ok?

      nil
    end
  end

  def stage_directory = directory.join(STAGE_DIRECTORIES.fetch(stage))

  def next_id
    id = @state["next_id"]
    @state["next_id"] += 1
    id
  end

  def high?(confidence) = confidence == AnnotationProposal::HIGH_CONFIDENCE
  def medium_or_high?(confidence) = WordCandidate::CONFIDENCES.include?(confidence) && confidence != AnnotationProposal::LOW_CONFIDENCE

  def entry_score_enough?(score)
    score.is_a?(Integer) && AnnotationProposal::ENTRY_SCORE_RANGE.cover?(score) && score > AnnotationProposal::ENTRY_CONCERN_MAX_SCORE
  end

  def reading_length_label(check)
    own = check.reading ? "#{check.reading} #{check.length}字" : "読みなし"
    check.mecab_reading ? "#{own} / MeCab #{check.mecab_reading} #{check.mecab_length}字" : own
  end

  # 語を順に見て、ブロックが理由を返したら却下、nil なら重複照合へ回す。通した語は以降の照合の相手になる。
  def sift(items, filter)
    passed = []
    rejected = []
    items.each_with_index do |item, index|
      reason = yield(item, index)
      reason ||= duplicate_reason(filter.match(item["surface"], item["reading"]))
      if reason
        rejected << [ item, reason ]
      else
        filter.remember(item["surface"], item["reading"])
        passed << item
      end
    end
    [ passed, rejected ]
  end

  def duplicate_reason(match)
    return unless match

    match.kind == :surface ? "重複: 表層形が〈#{match.surface}〉と一致" : "重複: 読みが〈#{match.surface}〉(#{match.reading})と一致"
  end

  # 出力 JSON の配列を取り出し、入力の語がすべて返っているかを確かめる。欠けていれば nil。
  def parse_output(text)
    key, expected, returned = case stage
    when "expand" then [ "seeds", seeds.map { |s| s["id"] }, ->(e) { e["id"].to_i } ]
    when "notation" then [ "words", words.map { |w| w["id"] }, ->(e) { e["id"].to_i } ]
    when "reading" then [ "words", words.map { |w| w["surface"] }, ->(e) { e["input"].to_s.strip } ]
    end
    entries = ResearchJson.array_at(text.to_s, key)
    return nil unless entries && (expected - entries.map(&returned)).empty?

    entries
  end

  # 段の結果を書き残して次の段へ進める。台帳の行は、却下した語と、最後の段を通って登録用に出した語。
  def record_stage(passed, rejected, ledger)
    rows = rejected.map { |word, reason| ledger_row("rejected", word, reason) }
    append_rejected(rejected)
    @state["report"] << { "stage" => stage, "input" => passed.size + rejected.size, "passed" => passed.size,
                          "rejected" => rejected.map { |_word, reason| reason[/\A[^(:]+/] }.tally }
    @state["words"] = passed
    @state["attempts"] = 0
    @state["stage"] = STAGES[STAGES.index(stage) + 1] || DONE

    if stage == DONE
      finish(passed)
      rows += passed.map { |word| ledger_row("output", word, nil).with(stage: STAGES.last) }
    end
    ledger.append(rows)
    save
  end

  # 一括登録に貼る 2 つ。step1 は表層形の一覧、step2 は /reading の出力のうち残った語だけ(形はそのまま)。
  def finish(passed)
    directory.join("register.txt").write(passed.map { |word| word["surface"] }.join("\n") + "\n")
    research = { "version" => "1", "words" => passed.map { |word| word["research"] } }
    directory.join("reading.json").write(JSON.pretty_generate(research) + "\n")
  end

  def append_rejected(rejected)
    return if rejected.empty?

    directory.join("rejected.tsv").open("a") do |file|
      rejected.each { |word, reason| file.puts([ stage, word["surface"], word["reading"], reason ].join("\t")) }
    end
  end

  def summary
    lines = [ "# 調査の自動実行 #{id}", "", "- 状態: #{stage}(失敗 #{attempts} 回)",
              "- 種語: #{seeds.map { |seed| seed["surface"] }.join("、")}", "- 公開語の写し: #{@state["corpus_fetched_at"] || "なし"}", "" ]
    @state["report"].each do |report|
      lines << "## #{report["stage"]}: #{report["input"]} 語 → 通過 #{report["passed"]} 語"
      report["rejected"].each { |reason, count| lines << "- 却下 #{reason}: #{count} 語" }
      lines << ""
    end
    lines << "一括登録へ: step1 に register.txt、step2 に reading.json を貼る。" if stage == DONE
    lines.join("\n") + "\n"
  end
end
