require "test_helper"
require "rake"

class BackfillTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("backfill:reading_metrics")
    Rake::Task["backfill:reading_metrics"].reenable
    Rake::Task["backfill:verify"].reenable
  end

  test "reading_metrics は last_char を含む派生値を埋め直す" do
    # コールバックを通さない直接更新で派生値を古い状態にする
    sense = word_senses(:curry) # 読み「カレー」: 末尾の長音を飛ばして last_char = レ
    sense.update_columns(rhythm_pattern: "stale", vowel_pattern: "stale", mora_count: 0, last_char: "陳")

    capture_io { Rake::Task["backfill:reading_metrics"].invoke }

    sense.reload
    assert_equal "karee", sense.rhythm_pattern
    assert_equal "aee", sense.vowel_pattern
    assert_equal 3, sense.mora_count
    assert_equal "レ", sense.last_char
  end

  test "reading_metrics は派生値が未設定(NULL)の語義も埋める" do
    # マイグレーション直後の既存行を再現(mora_count / vowel_pattern / last_char が NULL)
    sense = word_senses(:pending)
    sense.update_columns(vowel_pattern: nil, mora_count: nil, last_char: nil)

    capture_io { Rake::Task["backfill:reading_metrics"].invoke }

    sense.reload
    assert_equal "つ", sense.last_char # すずみやはるひのゆううつ
    assert_not_nil sense.mora_count
    assert_not_nil sense.vowel_pattern
  end

  test "verify は last_char の不整合を検出し報告する" do
    sense = word_senses(:curry)
    sense.update_columns(last_char: "陳")

    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }

    assert_includes out, "word_senses##{sense.id} last_char"
    assert_includes out, "不整合"
  end

  test "verify は char_type_pattern の不整合を検出し報告する" do
    word = words(:curry)
    word.update_columns(char_type_pattern: "漢漢漢")

    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }

    assert_includes out, "words##{word.id} char_type_pattern"
  end

  test "verify は不整合が無ければその旨だけを報告し、何も変更しない" do
    # pending フィクスチャは派生値が未設定のため、まず埋めてから検証する
    capture_io { Rake::Task["backfill:reading_metrics"].invoke }
    Rake::Task["backfill:verify"].reenable

    before_senses = WordSense.order(:id).pluck(:rhythm_pattern, :vowel_pattern, :mora_count, :last_char)

    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }

    assert_includes out, "派生カラムの不整合はありません"
    assert_equal before_senses, WordSense.order(:id).pluck(:rhythm_pattern, :vowel_pattern, :mora_count, :last_char)
  end
end
