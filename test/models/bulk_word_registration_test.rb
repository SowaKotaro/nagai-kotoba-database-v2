require "test_helper"

# 一括登録フォームオブジェクト(3ステップ: 入力→読み→重複→登録)。
# 読みの自動取得(ReadingExtractor)はスタブして安定させる。
class BulkWordRegistrationTest < ActiveSupport::TestCase
  # 表層形→読みの対応表でスタブし、ブロックを実行する。
  def with_readings(map)
    callable = ->(surfaces) { surfaces.map { |surface| map[surface] } }
    stub_method(ReadingExtractor, :call, callable) { yield }
  end

  # --- step2: bullet の除去 ---
  test "行頭の bullet(数字・ハイフン・中黒)を取り除いて表層形にする" do
    text = "1. 天上天下唯我独尊\n2) 花は桜木人は武士\n- 資本主義\n・精神"
    reg = BulkWordRegistration.new(text: text)

    with_readings({}) do
      entries = reg.extract_readings
      assert_equal %w[天上天下唯我独尊 花は桜木人は武士 資本主義 精神], entries.map(&:surface)
    end
  end

  test "空行は無視する" do
    reg = BulkWordRegistration.new(text: "1. 花\n\n\n2. 鳥")
    with_readings({}) do
      assert_equal %w[花 鳥], reg.extract_readings.map(&:surface)
    end
  end

  test "analyzable? は解析できる行があるかを返す" do
    assert BulkWordRegistration.new(text: "1. 花").analyzable?
    assert_not BulkWordRegistration.new(text: "\n\n").analyzable?
    assert_not BulkWordRegistration.new(text: "").analyzable?
  end

  # --- step2: 読みの付与 ---
  test "自動取得した読みをエントリに載せる" do
    reg = BulkWordRegistration.new(text: "1. 資本主義")
    with_readings("資本主義" => "シホンシュギ") do
      assert_equal "シホンシュギ", reg.extract_readings.first.reading
    end
  end

  # --- step2: reading_rows / 調査 JSON の突き合わせ ---
  test "reading_rows は MeCab の読みだけの行を返す(調査なし)" do
    reg = BulkWordRegistration.new(text: "1. 資本主義")
    with_readings("資本主義" => "シホンシュギ") do
      row = reg.reading_rows.first
      assert_equal "資本主義", row.surface
      assert_equal "シホンシュギ", row.chosen
      assert_equal :mecab_only, row.status
    end
  end

  # 調査 JSON をつくる小さなヘルパ。
  def research_json(*words)
    { version: "1", words: words }.to_json
  end

  test "MeCab と調査の読みが一致すれば match で MeCab を残す" do
    reg = BulkWordRegistration.new(
      entries: [ { surface: "資本主義", reading: "シホンシュギ" } ],
      research_json: research_json(input: "資本主義", surface: "資本主義", reading: "シホンシュギ", confidence: "high")
    )
    row = reg.merge_research.first
    assert_equal :match, row.status
    assert_equal "シホンシュギ", row.chosen
  end

  test "読みが不一致なら differ で既定は調査側を採用し、両候補を持つ" do
    reg = BulkWordRegistration.new(
      entries: [ { surface: "花は桜木人は武士", reading: "ハナハサクラギジンハブシ" } ],
      research_json: research_json(input: "花は桜木人は武士", surface: "花は桜木人は武士",
                                   reading: "ハナハサクラギヒトハブシ", confidence: "high")
    )
    row = reg.merge_research.first
    assert_equal :differ, row.status
    assert_equal "ハナハサクラギヒトハブシ", row.chosen
    assert_equal %w[ハナハサクラギジンハブシ ハナハサクラギヒトハブシ], row.candidates.map { |c| c[:reading] }
  end

  test "調査に無い語は mecab_only(MeCab の読みのまま)" do
    reg = BulkWordRegistration.new(
      entries: [ { surface: "猫", reading: "ネコ" } ],
      research_json: research_json(input: "犬", surface: "犬", reading: "イヌ", confidence: "high")
    )
    row = reg.merge_research.first
    assert_equal :mecab_only, row.status
    assert_equal "ネコ", row.chosen
  end

  test "MeCab が空で調査に読みがあれば research_only で調査側を採用" do
    reg = BulkWordRegistration.new(
      entries: [ { surface: "難読語", reading: "" } ],
      research_json: research_json(input: "難読語", surface: "難読語", reading: "ナンドクゴ", confidence: "medium")
    )
    row = reg.merge_research.first
    assert_equal :research_only, row.status
    assert_equal "ナンドクゴ", row.chosen
  end

  test "調査の alternatives も候補に含める" do
    reg = BulkWordRegistration.new(
      entries: [ { surface: "日本", reading: "ニホン" } ],
      research_json: research_json(input: "日本", surface: "日本", reading: "ニホン",
                                   alternatives: [ { reading: "ニッポン" } ], confidence: "high")
    )
    readings = reg.merge_research.first.candidates.map { |c| c[:reading] }
    assert_includes readings, "ニッポン"
  end

  test "壊れた調査 JSON は research_error? が真で全行 mecab_only" do
    reg = BulkWordRegistration.new(
      entries: [ { surface: "猫", reading: "ネコ" } ],
      research_json: "{ 壊れた"
    )
    assert reg.research_error?
    row = reg.merge_research.first
    assert_equal :mecab_only, row.status
    assert_equal "ネコ", row.chosen
  end

  test "```json フェンス付きで貼り付けても読める" do
    fenced = "```json\n#{research_json(input: '資本主義', surface: '資本主義', reading: 'シホンシュギ', confidence: 'high')}\n```"
    reg = BulkWordRegistration.new(
      entries: [ { surface: "資本主義", reading: "シホンシュギ" } ],
      research_json: fenced
    )
    row = reg.merge_research.first
    assert_not reg.research_error?
    assert_equal :match, row.status
  end

  # --- step3: 重複判定は確定した読み(entries)に対して行う ---
  test "読みが nil の語は重複判定で警告なし" do
    reg = BulkWordRegistration.new(entries: [ { surface: "未知語", reading: "" } ])
    entry = reg.analyze_duplicates.first
    assert_not entry.warnings?
  end

  test "バッチ内で読みが似ている語を相互に警告する" do
    # 類似度 = 1 - 1/7 ≒ 0.857(閾値0.8以上)
    reg = BulkWordRegistration.new(entries: [
      { surface: "殺人事件", reading: "サツジンジケン" },
      { surface: "殺人事", reading: "サツジンジケ" }
    ])
    analyzed = reg.analyze_duplicates
    assert analyzed[0].batch_matches.any?
    assert analyzed[1].batch_matches.any?
    assert_equal "サツジンジケ", analyzed[0].batch_matches.first.reading
  end

  test "読みが十分に異なればバッチ内警告は出ない" do
    reg = BulkWordRegistration.new(entries: [
      { surface: "猫", reading: "ネコ" },
      { surface: "資本主義", reading: "シホンシュギ" }
    ])
    analyzed = reg.analyze_duplicates
    assert_not analyzed[0].warnings?
    assert_not analyzed[1].warnings?
  end

  test "DB の既存読みに似た語を警告する(murder=さつじんじけん)" do
    reg = BulkWordRegistration.new(entries: [ { surface: "殺人事件", reading: "さつじんじけん" } ])
    entry = reg.analyze_duplicates.first
    assert entry.db_matches.any?
    match = entry.db_matches.first
    assert_equal "さつじんじけん", match.reading
    assert_in_delta 1.0, match.similarity, 0.0001
  end

  test "MeCab の誤読を直した読みで重複判定できる(直さないと取りこぼす例)" do
    # 誤読(サツジンジケン以外)では DB の murder に一致しないが、正しい読みなら一致する。
    wrong = BulkWordRegistration.new(entries: [ { surface: "殺人事件", reading: "ころしびとじけん" } ])
    assert_empty wrong.analyze_duplicates.first.db_matches

    fixed = BulkWordRegistration.new(entries: [ { surface: "殺人事件", reading: "さつじんじけん" } ])
    assert fixed.analyze_duplicates.first.db_matches.any?
  end

  # --- 登録 ---
  test "確認後のエントリを登録できる" do
    reg = BulkWordRegistration.new(entries: [
      { surface: "銀河鉄道の夜", reading: "ギンガテツドウノヨル" }
    ])

    assert_difference [ "Word.count", "WordSense.count" ], 1 do
      result = reg.register
      assert_equal 1, result.created
      assert_empty result.errors
    end
  end

  test "既存の(表層形,読み)はスキップする(冪等)" do
    reg = BulkWordRegistration.new(entries: [
      { surface: words(:abc_murder).surface, reading: word_senses(:murder).reading }
    ])

    assert_no_difference [ "Word.count", "WordSense.count" ] do
      result = reg.register
      assert_equal 1, result.skipped
    end
  end

  test "読みが空のエントリはエラーになる" do
    reg = BulkWordRegistration.new(entries: [ { surface: "読みなし", reading: "" } ])
    result = reg.register
    assert_equal 0, result.created
    assert_equal 1, result.errors.size
  end

  test "表層形が空のエントリは取り込まれない" do
    reg = BulkWordRegistration.new(entries: [ { surface: "  ", reading: "ヨミ" } ])
    assert_not reg.registerable?
  end

  test "_exclude にチェックした行は登録に含めない" do
    reg = BulkWordRegistration.new(entries: [
      { surface: "登録する", reading: "トウロクスル" },
      { surface: "除外する", reading: "ジョガイスル", _exclude: "1" }
    ])

    assert_difference [ "Word.count", "WordSense.count" ], 1 do
      result = reg.register
      assert_equal 1, result.created
    end
    assert Word.exists?(surface: "登録する")
    assert_not Word.exists?(surface: "除外する")
  end
end
