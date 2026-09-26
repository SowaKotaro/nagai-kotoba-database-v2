require "test_helper"

class WordCandidateExpansionImportTest < ActiveSupport::TestCase
  setup do
    @seed = WordCandidate.create!(surface: "泥門デビルバッツ", status: :expanding)
  end

  def import(seeds)
    WordCandidateExpansionImport.new({ version: "1", seeds: seeds }.to_json).call
  end

  test "集めた語を元の語・系統の根に結び付けて仕分け待ちに入れ、元の語も拡張済みの印を立てて仕分けに戻す(元の語自身と空行は入れない)" do
    result = import([ { id: @seed.id, input: @seed.surface, words: [ "泥門デビルバッツ", "神龍寺ナーガ", " " ], note: "軸: チーム名" } ])

    @seed.reload
    assert_predicate @seed, :triage?
    assert_predicate @seed.expanded_at, :present?
    assert_equal "軸: チーム名", @seed.note
    child = WordCandidate.find_by!(surface: "神龍寺ナーガ")
    assert_predicate child, :triage?
    assert_nil child.expanded_at
    assert_equal [ @seed, @seed.id ], [ child.seed, child.root_id ]
    assert_equal({ created: 1, seeds: 1 }, result.counts.symbolize_keys.slice(:created, :seeds))
  end

  test "拡張を見送った(words が空の)元の語も仕分けに戻す" do
    import([ { id: @seed.id, words: [], note: "拡張見送り: 有望な軸なし" } ])

    @seed.reload
    assert_predicate @seed, :triage?
    assert_equal "拡張見送り: 有望な軸なし", @seed.note
  end

  test "すでに入っている語(不要にした語を含む)・収録済みの語は入れない" do
    WordCandidate.create!(surface: "不要にした言葉", status: :rejected)

    result = import([ { id: @seed.id, words: [ "不要にした言葉", words(:curry).surface ] } ])

    assert_equal 1, result.counts[:existing]
    assert_equal 1, result.counts[:registered]
    assert_equal 0, result.counts[:created]
  end

  test "入れられない語(長すぎる語)は理由を添えて行のエラーにし、ほかの語は入れる" do
    result = import([ { id: @seed.id, words: [ "長" * 256, "神龍寺ナーガ" ] } ])

    assert_equal [ 1, 1 ], result.counts.values_at(:errors, :created)
    assert_match(/\A長+: 表層形 は255文字以内/, result.messages.first)
  end

  test "拡張待ちにいない語と存在しない ID は見送り、同じ JSON を2回貼っても増えない" do
    json = [ { id: @seed.id, words: [ "神龍寺ナーガ" ] }, { id: 0, input: "無い語", words: [ "何か" ] } ]
    import(json)
    result = import(json)

    assert_equal 1, result.counts[:stale]
    assert_equal 1, result.counts[:unknown]
    assert_equal 2, WordCandidate.count
  end

  test "形の違う JSON は nil(コードフェンスは剥がして読む)" do
    assert_nil WordCandidateExpansionImport.new("not json").call
    assert_nil WordCandidateExpansionImport.new({ words: [] }.to_json).call
    fenced = "```json\n#{({ seeds: [] }.to_json)}\n```"
    assert_not_nil WordCandidateExpansionImport.new(fenced).call
  end
end
