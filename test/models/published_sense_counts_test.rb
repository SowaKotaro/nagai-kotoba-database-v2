require "test_helper"

class PublishedSenseCountsTest < ActiveSupport::TestCase
  # 公開語はフィクスチャの ABC殺人事件(さつじんじけん・7字)と カレーライス(カレー・3字)。
  # 未注釈の 涼宮ハルヒの憂鬱 / バミューダトライアングル は数えない。

  test "先頭・末尾の文字、読みの文字数・モーラ数、ジャンル・エンティティ・言語学的特徴ごとの公開語義数を数える" do
    counts = PublishedSenseCounts.by_first_char
    assert_equal 1, counts["さ"]
    assert_equal 1, counts["カ"]
    assert_nil counts["す"] # 未注釈の すずみやはるひのゆううつ は含めない

    # 末尾の文字(さつじんじけん → ん / カレー → レ)。未注釈の すずみやはるひのゆううつ(つ)は含めない
    assert_equal({ "ん" => 1, "レ" => 1 }, PublishedSenseCounts.by_last_char)

    # 読みの文字数ごとの公開語義数を数える
    counts = PublishedSenseCounts.by_reading_length
    assert_equal 1, counts[7]
    assert_equal 1, counts[3]
    assert_nil counts[12] # 未注釈の 12 字は含めない

    # モーラ数(さつじんじけん 7・カレー 3)。未注釈の 12 モーラは含めない
    assert_equal({ 7 => 1, 3 => 1 }, PublishedSenseCounts.by_mora_count)

    # 小分類ジャンルごとの公開語義数を数える
    counts = PublishedSenseCounts.by_genre
    assert_equal 1, counts[genres(:small_novel).id]
    # ジャンル未設定の語義は nil キーにまとまる
    assert_equal 1, counts[nil]

    # エンティティも同じく、未設定の語義(カレー)は nil キーにまとまる
    assert_equal({ entity_types(:book_title).id => 1, nil => 1 }, PublishedSenseCounts.by_entity_type)

    # 言語学的特徴は語義の数で数える(同じ語義に 2 か所付いても 1。未注釈の語義に付いたものは数えない)
    WordSenseFeature.create!(word_sense: word_senses(:murder), linguistic_feature: linguistic_features(:rendaku),
                             target: "事件", target_reading: "じけん", target_start: 5)
    WordSenseFeature.create!(word_sense: word_senses(:pending), linguistic_feature: linguistic_features(:rendaku),
                             target: "憂鬱", target_reading: "ゆううつ", target_start: 6)
    assert_equal({ linguistic_features(:rendaku).id => 1, linguistic_features(:jubako).id => 1 },
                 PublishedSenseCounts.by_linguistic_feature)
  end

  test "集計はキャッシュされ、期限内は数え直さない" do
    with_rails_cache do
      assert_equal 1, PublishedSenseCounts.by_first_char["さ"]

      # キャッシュが効いていれば、その後に公開した語はまだ現れない。
      create_published_word(surface: "追加した語", reading: "ツイカシタゴ")
      assert_nil PublishedSenseCounts.by_first_char["ツ"]

      # 期限が切れれば数え直す。
      travel_to(PublishedSenseCounts::CACHE_TTL.from_now + 1.minute) do
        assert_equal 1, PublishedSenseCounts.by_first_char["ツ"]
      end
    end
  end
end
