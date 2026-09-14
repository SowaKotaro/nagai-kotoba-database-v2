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
    # フィクスチャの派生値は読み・表層形と整合させてある(ずれていればここで検出される)
    before_senses = WordSense.order(:id).pluck(:rhythm_pattern, :vowel_pattern, :mora_count, :last_char)

    out, _err = capture_io { Rake::Task["backfill:verify"].invoke }

    assert_includes out, "派生カラムの不整合はありません"
    assert_equal before_senses, WordSense.order(:id).pluck(:rhythm_pattern, :vowel_pattern, :mora_count, :last_char)
  end
end
