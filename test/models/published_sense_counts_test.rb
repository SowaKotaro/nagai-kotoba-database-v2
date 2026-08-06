require "test_helper"

class PublishedSenseCountsTest < ActiveSupport::TestCase
  # 公開語はフィクスチャの ABC殺人事件(さつじんじけん・7字)と カレーライス(カレー・3字)。
  # 未注釈の 涼宮ハルヒの憂鬱 / バミューダトライアングル は数えない。

  test "先頭文字ごとの公開語義数を数える" do
    counts = PublishedSenseCounts.by_first_char
    assert_equal 1, counts["さ"]
    assert_equal 1, counts["カ"]
    assert_nil counts["す"] # 未注釈の すずみやはるひのゆううつ は含めない
  end

  test "読みの文字数ごとの公開語義数を数える" do
    counts = PublishedSenseCounts.by_reading_length
    assert_equal 1, counts[7]
    assert_equal 1, counts[3]
    assert_nil counts[12] # 未注釈の 12 字は含めない
  end

  test "小分類ジャンルごとの公開語義数を数える" do
    counts = PublishedSenseCounts.by_genre
    assert_equal 1, counts[genres(:small_novel).id]
    # ジャンル未設定の語義は nil キーにまとまる
    assert_equal 1, counts[nil]
  end

  test "集計はキャッシュされ、期限内は数え直さない" do
    with_memory_cache do
      assert_equal 1, PublishedSenseCounts.by_first_char["さ"]

      # キャッシュが効いていれば、その後に公開した語はまだ現れない。
      word = Word.create!(surface: "追加した語", annotated_at: Time.current)
      word.word_senses.create!(reading: "ツイカシタゴ")
      assert_nil PublishedSenseCounts.by_first_char["ツ"]

      # 期限が切れれば数え直す。
      travel_to(PublishedSenseCounts::CACHE_TTL.from_now + 1.minute) do
        assert_equal 1, PublishedSenseCounts.by_first_char["ツ"]
      end
    end
  end

  private

  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end
end
