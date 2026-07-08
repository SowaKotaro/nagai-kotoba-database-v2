# 単語(表層形)を箇条書きテキストからまとめて登録するフォームオブジェクト。
# 登録は3ステップに分ける:
#   [step1 入力] text(箇条書き)を受け取る。
#   [step2 読み] MeCab で読みを自動取得する(#extract_readings)。画面で読みを確認・編集する。
#                ※将来 LLM 等で読みを強化する差し込み口も、この段で readings を差し替えれば済む。
#   [step3 重複] 確定した読み(entries)で重複・類似(バッチ内 / DB 内)を判定する(#analyze_duplicates)。
#                重複判定は「確定後の読み」に対して行うため、MeCab の誤読で取りこぼしにくい。
#   [登録] 除外されなかったエントリ(表層形+読み)を登録する(#register)。
#
# 箇条書きの bullet(行頭の「1.」「-」「・」など)は取り除き、残りを表層形として扱う。
# 登録はジャンル等を付けず未注釈のまま行い、後段のアノテーションで整える。
# 冪等: 既存の(表層形,読み)はスキップする。重複・類似は警告のみで、登録は妨げない。
class BulkWordRegistration
  include ActiveModel::Model

  # 解析フェーズの入力(箇条書きテキスト)。
  attr_accessor :text
  # step2 の任意入力: オフライン調査(word-reading-research skill)の出力 JSON。
  # 貼られていれば MeCab の暫定読みと突き合わせて確定読みを選ぶ。
  attr_accessor :research_json
  # 登録フェーズの入力(確認・編集後のエントリ配列)。
  attr_reader :entries

  # 読みの正規化類似度がこの値以上なら「似ている」とみなして警告する。
  SIMILARITY_THRESHOLD = 0.8

  # 行頭の bullet: 「1.」「2)」「-」「*」「・」など。
  BULLET = /\A\s*(?:\d+[.)．、:：]|[-*・‣▪●○])\s*/

  # 登録するエントリ(表層形+読み)。
  Entry = Struct.new(:surface, :reading, keyword_init: true)
  # 解析結果の1件。似ている相手(バッチ内 / DB 内)を保持し、確認画面で警告表示する。
  AnalyzedEntry = Struct.new(:index, :surface, :reading, :batch_matches, :db_matches, keyword_init: true) do
    def warnings?
      batch_matches.any? || db_matches.any?
    end
  end
  # 似ている相手の情報(表示用)。
  Match = Struct.new(:surface, :reading, :similarity, keyword_init: true)
  # 登録結果の集計。created=新規登録, skipped=既存, errors=登録できなかった行の説明。
  Result = Struct.new(:created, :skipped, :errors, keyword_init: true)

  # step2 の確認行。MeCab の暫定読みと、調査 JSON の読み(＋候補)を突き合わせた結果。
  # status: :mecab_only(調査なし) / :match(一致) / :differ(不一致) / :research_only(MeCab空)。
  # chosen が初期選択の読み(不一致は調査側を採用)。candidates はチップに出す候補。
  MergedEntry = Struct.new(
    :surface, :mecab_reading, :research_reading, :research_alternatives, :research_confidence, :chosen, :status,
    keyword_init: true
  ) do
    def match? = status == :match
    def differ? = status == :differ

    # 読み欄に流し込める候補(重複読みは除く)。source は mecab / research / alt。
    def candidates
      list = []
      list << { reading: mecab_reading, source: "mecab" } if mecab_reading.present?
      list << { reading: research_reading, source: "research" } if research_reading.present?
      Array(research_alternatives).each { |reading| list << { reading: reading, source: "alt" } }
      list.uniq { |candidate| candidate[:reading] }
    end
  end

  # --- step2: 読みの自動取得 ---

  # 箇条書き(text)を表層形に分解し、MeCab で読みを自動取得した Entry 配列を返す。
  # ここでは重複・類似の判定はしない(step3 で確定後の読みに対して行う)。
  def extract_readings
    surfaces = parsed_surfaces
    readings = ReadingExtractor.call(surfaces)
    surfaces.each_index.map { |i| Entry.new(surface: surfaces[i], reading: readings[i]) }
  end

  # step2 初期表示の行(MeCab の読みのみ。調査 JSON はまだ無い)。
  def reading_rows
    extract_readings.map do |entry|
      MergedEntry.new(surface: entry.surface, mecab_reading: entry.reading, research_alternatives: [],
                      chosen: entry.reading, status: :mecab_only)
    end
  end

  # step2: entries(現在の読み)に調査 JSON を突き合わせ、確定候補つきの行を返す。
  def merge_research
    index = research_index
    Array(entries).map { |entry| build_merged_entry(entry, index[entry.surface]) }
  end

  # 調査 JSON のパースに失敗したか(不正な JSON を貼られたとき)。
  def research_error?
    research_index
    @research_error == true
  end

  # 読み取得に使えるテキストがあるか(空なら step2 へ進めない)。
  def analyzable?
    parsed_surfaces.any?
  end

  # --- step3: 重複・類似の判定 ---

  # 確定した読み(entries)で重複・類似(バッチ内 / DB 内)を判定した AnalyzedEntry 配列を返す。
  # DB への書き込みは行わない。
  def analyze_duplicates
    analyzed = Array(entries).each_with_index.map do |entry, i|
      AnalyzedEntry.new(index: i, surface: entry.surface, reading: entry.reading, batch_matches: [], db_matches: [])
    end

    attach_batch_matches(analyzed)
    attach_db_matches(analyzed)
    analyzed
  end

  # --- 登録フェーズ ---

  # 確認画面から送られたエントリ(表層形+読み)を取り込む。
  # 「除外」にチェックされた行(_exclude)と、表層形が空の行は登録に含めない。
  def entries=(rows)
    @entries = Array(rows).filter_map do |row|
      next if truthy?(row[:_exclude])

      surface = row[:surface].to_s.strip
      next if surface.blank?

      Entry.new(surface: surface, reading: row[:reading].to_s.strip)
    end
  end

  # 取り込んだエントリを登録する。行ごとに独立して処理し、結果(Result)を返す。
  def register
    created = 0
    skipped = 0
    errors = []

    Array(entries).each do |entry|
      if entry.reading.blank?
        errors << error_line(entry.surface, I18n.t("admin.words.bulk.errors.missing_reading"))
        next
      end

      case (outcome = register_one(entry.surface, entry.reading))
      when :created then created += 1
      when :skipped then skipped += 1
      else errors << error_line(entry.surface, outcome)
      end
    end

    Result.new(created: created, skipped: skipped, errors: errors)
  end

  # 登録できるエントリがあるか。
  def registerable?
    Array(entries).any?
  end

  private

  # 1件を登録する。:created / :skipped、失敗時はエラーメッセージ文字列を返す。
  # 表層形の作成と読みの追加は1件単位でトランザクションにまとめる。
  def register_one(surface, reading)
    ActiveRecord::Base.transaction do
      word = Word.find_or_create_by!(surface: surface)
      sense = word.word_senses.find_or_initialize_by(reading: reading)
      next :skipped if sense.persisted?

      sense.save!
      :created
    end
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.full_messages.join("、")
  end

  # バッチ内で読みが似ているエントリ同士を相互に警告として結び付ける。
  def attach_batch_matches(analyzed)
    analyzed.combination(2).each do |a, b|
      next if a.reading.blank? || b.reading.blank?
      next if too_different?(a.reading, b.reading)

      sim = Levenshtein.similarity(a.reading, b.reading)
      next if sim < SIMILARITY_THRESHOLD

      a.batch_matches << Match.new(surface: b.surface, reading: b.reading, similarity: sim)
      b.batch_matches << Match.new(surface: a.surface, reading: a.reading, similarity: sim)
    end
    analyzed.each { |e| e.batch_matches.sort_by! { |m| -m.similarity } }
  end

  # DB に既存の読みと似ているエントリへ警告を結び付ける。
  def attach_db_matches(analyzed)
    analyzed.each do |entry|
      next if entry.reading.blank?

      entry.db_matches.concat(db_matches_for(entry.reading))
    end
  end

  def db_matches_for(reading)
    existing_readings.filter_map do |existing_reading, existing_surface|
      next if too_different?(reading, existing_reading)

      sim = Levenshtein.similarity(reading, existing_reading)
      Match.new(surface: existing_surface, reading: existing_reading, similarity: sim) if sim >= SIMILARITY_THRESHOLD
    end.sort_by { |m| -m.similarity }
  end

  # DB の既存 (読み, 表層形) 一覧。1回だけ読み込んでメモ化する。
  def existing_readings
    @existing_readings ||= WordSense.joins(:word).distinct.pluck("word_senses.reading", "words.surface")
  end

  # 長さの差が大きすぎて類似度が閾値に届かない組を、距離計算の前に安価に弾く。
  # 編集距離は最低でも文字数の差だけかかるため、|差| が (1-閾値)×長い方 を超えたら閾値未満で確定。
  def too_different?(a, b)
    longest = [ a.length, b.length ].max
    return false if longest.zero?

    (a.length - b.length).abs > (1 - SIMILARITY_THRESHOLD) * longest
  end

  # 各行から bullet を除いた表層形の配列(空行はスキップ)。
  def parsed_surfaces
    text.to_s.each_line.filter_map do |raw|
      line = raw.strip
      next if line.blank?

      line.sub(BULLET, "").strip.presence
    end
  end

  # 調査 JSON を { 表層形 => { reading:, alternatives:, confidence: } } に索引化する。
  # input と surface の両方をキーにする(step2 は表層形で突き合わせる)。パース失敗時は空。
  def research_index
    return @research_index if defined?(@research_index)

    @research_error = false
    @research_index = parse_research_words.each_with_object({}) do |word, index|
      next unless word.is_a?(Hash)

      data = {
        reading: normalize_reading(word["reading"]),
        alternatives: Array(word["alternatives"]).filter_map { |alt| normalize_reading(alt.is_a?(Hash) ? alt["reading"] : alt) },
        confidence: word["confidence"]
      }
      %w[input surface].each do |key|
        surface = word[key].to_s.strip
        index[surface] ||= data if surface.present?
      end
    end
  end

  # 調査 JSON の words 配列を取り出す。空や不正な JSON は空配列(＋エラーフラグ)。
  def parse_research_words
    return [] if research_json.blank?

    parsed = JSON.parse(strip_code_fence(research_json))
    words = parsed.is_a?(Hash) ? parsed["words"] : nil
    words.is_a?(Array) ? words : (@research_error = true) && []
  rescue JSON::ParserError
    @research_error = true
    []
  end

  # チャット等からの貼り付けで付いてくる ```json フェンスを剥がす(前後の空白も含めて)。
  def strip_code_fence(json_text)
    json_text.to_s.strip.sub(/\A```(?:json)?\s*\n/, "").sub(/\n?```\z/, "")
  end

  # entries の1件と、対応する調査データから MergedEntry を組み立てる。
  def build_merged_entry(entry, research)
    mecab = entry.reading.to_s.strip

    if research.nil?
      return MergedEntry.new(surface: entry.surface, mecab_reading: mecab.presence, research_alternatives: [],
                             chosen: mecab, status: :mecab_only)
    end

    research_reading = research[:reading].to_s
    status =
      if mecab.blank? && research_reading.present? then :research_only
      elsif research_reading.blank? then :mecab_only
      elsif mecab == research_reading then :match
      else :differ
      end
    # 不一致・調査のみは調査側を初期採用(誤読の是正が目的)。一致・調査なしは MeCab を残す。
    chosen = %i[differ research_only].include?(status) ? research_reading : mecab

    MergedEntry.new(surface: entry.surface, mecab_reading: mecab.presence, research_reading: research_reading.presence,
                    research_alternatives: research[:alternatives], research_confidence: research[:confidence],
                    chosen: chosen, status: status)
  end

  # 読みの前処理: 前後空白を除く(空なら nil)。
  def normalize_reading(reading)
    reading.to_s.strip.presence
  end

  # チェックボックス等の真偽表現("1"/"true"/true)を判定する。
  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def error_line(surface, detail)
    I18n.t("admin.words.bulk.error_line", surface: surface, detail: detail)
  end
end
