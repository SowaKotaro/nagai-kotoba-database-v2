require "test_helper"

# 言語学的特徴の点検結果の読み取り(FeatureAuditImport)と、選んだ行の適用(FeatureAuditApplication)。Issue 109。
class FeatureAuditImportTest < ActiveSupport::TestCase
  setup do
    @word = create_published_word(surface: "手紙の書き方", reading: "テガミノカキカタ")
    @sense = @word.word_senses.first
    @sense.word_sense_features.create!(linguistic_feature: linguistic_features(:jubako), target: "書き", target_reading: "カキ")
  end

  def change(action:, name: "連濁", target: "手紙", target_reading: "テガミ", sense_id: @sense.id, word_id: @word.id)
    { "action" => action, "word_id" => word_id, "sense_id" => sense_id, "name" => name,
      "target" => target, "target_reading" => target_reading, "reason" => "理由" }
  end

  def rows_for(*changes)
    FeatureAuditImport.new({ "version" => "1", "changes" => changes }.to_json).rows
  end

  test "行ごとに検証し、適用できない理由を problem に入れる" do
    cases = {
      change(action: "add") => nil,
      change(action: "remove", name: "重箱読み", target: "書き") => nil,
      change(action: "replace") => :unknown_action,
      change(action: "add", sense_id: 0) => :sense_not_found,
      change(action: "add", word_id: @word.id + 999) => :sense_not_found,
      change(action: "add", name: "無い特徴") => :unknown_feature,
      change(action: "add", target: "") => :missing_target,
      change(action: "add", target_reading: "") => :missing_target_reading,
      change(action: "add", target: "葉書") => :target_not_in_surface,
      change(action: "add", target_reading: "ハガキ") => :target_reading_not_in_reading,
      change(action: "add", name: "重箱読み", target: "書き", target_reading: "カキ") => :already_attached,
      change(action: "remove", target: "手紙") => :not_attached
    }
    cases.each do |entry, expected|
      problem = rows_for(entry).first.problem
      expected.nil? ? assert_nil(problem, entry.inspect) : assert_equal(expected, problem, entry.inspect)
    end

    # 同じ変更が2度あれば、後ろの行を重複として外す
    assert_equal [ nil, :duplicate ], rows_for(change(action: "add"), change(action: "add")).map(&:problem)
    # ```json のフェンスは剥がして読み、形が違えば nil
    fenced = "```json\n#{({ "changes" => [ change(action: "add") ] }).to_json}\n```"
    assert_equal 1, FeatureAuditImport.new(fenced).rows.size
    assert_nil FeatureAuditImport.new("読めない").rows
    assert_nil FeatureAuditImport.new({ "proposals" => [] }.to_json).rows
  end

  test "選んだ行のうち、検証に通った行だけを足し・外し、語の updated_at を動かす" do
    rows = rows_for(change(action: "add"),
                    change(action: "remove", name: "重箱読み", target: "書き"),
                    change(action: "add", target: "葉書"))
    unselected = rows_for(change(action: "add"))

    # 選ばなかった行は適用しない
    assert_no_difference -> { WordSenseFeature.count } do
      FeatureAuditApplication.new(unselected, []).apply
    end

    travel_to 1.hour.from_now do
      result = FeatureAuditApplication.new(rows, [ 0, 1, 2 ]).apply

      assert_equal [ 1, 1, 1 ], [ result.added, result.removed, result.words ]
      assert_equal [ [ "連濁", "手紙", "テガミ" ] ],
                   @sense.reload.word_sense_features.map { |f| [ f.linguistic_feature.name, f.target, f.target_reading ] }
      assert_in_delta Time.current, @word.reload.updated_at, 1.second
    end
  end
end
