require "test_helper"

class ResearchLedgerTest < ActiveSupport::TestCase
  test "追記した行を読み戻し、照合の相手からは種語とその run 自身の行を除く" do
    Dir.mktmpdir do |dir|
      ledger = ResearchLedger.new(File.join(dir, "auto/ledger.tsv"))
      assert_equal [], ledger.rows

      row = ->(run_id, kind, surface, reading = nil) {
        ResearchLedger::Row.new(recorded_on: "2026-11-13", run_id:, kind:, outcome: "rejected", stage: "expand",
                                surface:, reading:, reason: "理由\tタブ入り")
      }
      ledger.append([ row.call("a", "seed", "種語"), row.call("a", "word", "語A", "ゴエー"), row.call("b", "word", "語B") ])

      assert_equal 3, ledger.rows.size
      assert_equal "理由 タブ入り", ledger.rows.first.reason # タブは列を壊さないよう空白に置き換える
      assert_equal Set["種語"], ledger.used_seeds
      assert_equal [ [ "語A", "ゴエー" ], [ "語B", nil ] ], ledger.known_words
      assert_equal [ [ "語A", "ゴエー" ] ], ledger.known_words(except_run: "b")
    end
  end
end
