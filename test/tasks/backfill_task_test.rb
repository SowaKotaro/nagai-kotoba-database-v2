require "test_helper"
require "rake"

# 派生カラムの修復用タスク。update_all や直接 SQL で読み・表層形をいじったあとの修復に使う。
class BackfillTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("backfill:reading_metrics")
    Rake::Task["backfill:reading_metrics"].reenable
    Rake::Task["backfill:verify"].reenable
  end

  test "reading_metrics は古くなった値も未設定(NULL)の値も、last_char を含めて埋め直す" do
    # コールバックを通さない直接更新で、派生値を古い状態・未設定の状態にする
    stale = word_senses(:curry) # 読み「カレー」: 末尾の長音を飛ばして last_char = レ
    stale.update_columns(rhythm_pattern: "stale", vowel_pattern: "stale", mora_count: 0, last_char: "陳")
    blank = word_senses(:pending) # 読み「すずみやはるひのゆううつ」
    blank.update_columns(vowel_pattern: nil, mora_count: nil, last_char: nil)

    capture_io { Rake::Task["backfill:reading_metrics"].invoke }

    stale.reload
    assert_equal [ "karee", "aee", 3, "レ" ], [ stale.rhythm_pattern, stale.vowel_pattern, stale.mora_count, stale.last_char ]
    blank.reload
    assert_equal [ "uuiaauiouuuu", 12, "つ" ], [ blank.vowel_pattern, blank.mora_count, blank.last_char ]
  end

  METRIC_COLUMNS = %w[sense_count variant_count feature_count min_reading_length max_reading_length max_mora_count
                      max_small_kana_count max_chouon_count max_dakuten_count min_ring_crossing_count
                      max_ring_crossing_count min_reading max_reading min_reversed_reading].freeze

  test "sense_metrics は、直接更新で崩した words の代表値を元に戻す" do
    WordSenseMetrics.refresh!
    expected = Word.order(:id).pluck(*METRIC_COLUMNS)

    # コールバックを通さない直接更新で、全語の代表値を崩す
    Word.update_all(sense_count: 99, variant_count: 99, feature_count: 99, min_reading_length: 1, max_reading_length: 1,
                    max_mora_count: 0, min_ring_crossing_count: 99, max_ring_crossing_count: 99,
                    min_reading: "崩", max_reading: "崩", min_reversed_reading: "崩")
    assert_not_equal expected, Word.order(:id).pluck(*METRIC_COLUMNS)

    Rake::Task["backfill:sense_metrics"].reenable
    capture_io { Rake::Task["backfill:sense_metrics"].invoke }

    assert_equal expected, Word.order(:id).pluck(*METRIC_COLUMNS)
    curry = words(:curry).reload
    assert_equal [ 1, 1, 3, "カレー" ], [ curry.sense_count, curry.variant_count, curry.max_reading_length, curry.max_reading ]
  end

  test "verify は last_char・char_type_pattern の不整合を報告する" do
    sense = word_senses(:curry)
    sense.update_columns(last_char: "陳")
    word = words(:curry)
    word.update_columns(char_type_pattern: "漢漢漢")

    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }

    assert_includes out, "word_senses##{sense.id} last_char"
    assert_includes out, "words##{word.id} char_type_pattern"
    assert_includes out, "不整合: 2 件"
  end

  test "verify は不整合が無ければその旨だけを報告し、何も変更しない" do
    # フィクスチャの派生値は読み・表層形と整合させてある(円環交差数も)。words の代表値は test_helper の
    # setup で焼き直してある。どれかがずれていれば、ここで検出される
    sense_columns = WordSense.reading_derivations("").keys
    before_senses = WordSense.order(:id).pluck(*sense_columns)
    before_words = Word.order(:id).pluck(*METRIC_COLUMNS)

    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }

    assert_includes out, "派生カラムの不整合はありません"
    assert_equal before_senses, WordSense.order(:id).pluck(*sense_columns)
    assert_equal before_words, Word.order(:id).pluck(*METRIC_COLUMNS)
  end

  # 円環交差数は、ほかの読み由来の値より後(2026-07-21)に足した列で、以前は修復タスクの対象から漏れていた。
  test "円環交差数を崩すと verify が語義と words の代表値の両方を報告し、reading_metrics がまとめて直す" do
    sense = word_senses(:curry)
    original = sense.ring_crossing_count
    sense.update_columns(ring_crossing_count: 99) # コールバックを通らないので、words の代表値は崩す前の値のまま

    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }
    assert_includes out, "word_senses##{sense.id} ring_crossing_count: 99 → #{original}"
    assert_includes out, "words##{sense.word_id} min_ring_crossing_count: #{original} → 99"
    assert_includes out, "不整合: 3 件"

    capture_io { Rake::Task["backfill:reading_metrics"].invoke }
    assert_equal original, sense.reload.ring_crossing_count
    assert_equal [ original, original ], words(:curry).reload.values_at(:min_ring_crossing_count, :max_ring_crossing_count)

    Rake::Task["backfill:verify"].reenable
    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }
    assert_includes out, "派生カラムの不整合はありません"
  end

  test "verify は words の代表値のずれも報告する(直すのは sense_metrics)" do
    words(:curry).update_columns(sense_count: 5, max_reading: "崩")

    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }

    assert_includes out, "words##{words(:curry).id} sense_count: 5 → 1"
    assert_includes out, "words##{words(:curry).id} max_reading: \"崩\" → \"カレー\""
    assert_includes out, "不整合: 2 件"
  end

  # CLAUDE.md・docs/data-model.md §3 の修復手順: 読みを直接書き換えたら、verify で見つけ、reading_metrics で直す。
  test "読みを直接書き換えたあと、verify が見つけ、reading_metrics だけで語義と words の代表値がそろう" do
    sense = word_senses(:curry)
    sense.update_columns(reading: "カレーライス") # コールバックを通らない(reading_length だけは STORED で追従する)

    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }
    assert_includes out, "word_senses##{sense.id} rhythm_pattern"
    assert_includes out, "words##{sense.word_id} max_reading_length: 3 → 6"

    capture_io { Rake::Task["backfill:reading_metrics"].invoke }
    assert_equal [ "kareeraisu", 6 ], sense.reload.values_at(:rhythm_pattern, :mora_count)
    curry = words(:curry).reload
    assert_equal [ 6, "カレーライス" ], [ curry.max_reading_length, curry.max_reading ]
    # reading_density は STORED だが、max_reading_length(代表値)から作るので代表値と一緒に追従する
    assert_equal (BigDecimal("6") / curry.surface_length).round(4), curry.reading_density

    Rake::Task["backfill:verify"].reenable
    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }
    assert_includes out, "派生カラムの不整合はありません"
  end
end
