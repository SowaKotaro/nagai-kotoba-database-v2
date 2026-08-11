require "test_helper"

class LevenshteinTest < ActiveSupport::TestCase
  test "同一文字列の距離は0" do
    assert_equal 0, Levenshtein.distance("さつじん", "さつじん")
  end

  test "片方が空なら距離はもう片方の文字数" do
    assert_equal 4, Levenshtein.distance("", "さつじん")
    assert_equal 4, Levenshtein.distance("さつじん", "")
    assert_equal 0, Levenshtein.distance("", "")
  end

  test "置換・挿入・削除の距離" do
    assert_equal 1, Levenshtein.distance("ねこ", "ねご")   # 置換1
    assert_equal 1, Levenshtein.distance("ねこ", "ねこん") # 挿入1
    assert_equal 1, Levenshtein.distance("ねこん", "ねこ") # 削除1
    assert_equal 3, Levenshtein.distance("kitten", "sitting")
  end

  test "類似度は 0.0〜1.0 で完全一致が1.0" do
    assert_in_delta 1.0, Levenshtein.similarity("さつじん", "さつじん"), 0.0001
    assert_in_delta 1.0, Levenshtein.similarity("", ""), 0.0001
  end

  test "類似度は長い方の文字数で正規化する" do
    # 距離1 / 長さ4(置換1) → 0.75
    assert_in_delta 0.75, Levenshtein.similarity("サツジン", "サツジソ"), 0.0001
    # 距離1 / 長さ3(挿入1) → 約0.667
    assert_in_delta(1.0 - (1.0 / 3), Levenshtein.similarity("ねこ", "ねこん"), 0.0001)
  end

  test "全く異なる読みの類似度は低い" do
    assert Levenshtein.similarity("さつじんじけん", "カレー") < 0.5
  end

  test "far_apart? は文字数差だけで足切りする" do
    # 距離を計算するまでもなく、しきい値(0.8)に届かないほど長さが違う組
    assert Levenshtein.far_apart?("アイウエオカキクケコ", "アイウ")
    refute Levenshtein.far_apart?("アイウエオカキクケコ", "アイウエオカキクケ")
  end

  test "far_apart? はしきい値ちょうどの組を弾かない" do
    # 読み10字・文字数差2 は最短でも距離2 = 類似度ちょうど 0.8 で「似ている」側。
    # (1 - 0.8) が倍精度で 0.19999999999999996 になるため、素朴に書くと
    # ここを取りこぼす。境界の回帰テスト。
    a = "アイウエオカキクケコ"
    b = "アイウエオカキク"
    assert_in_delta 0.8, Levenshtein.similarity(a, b), 0.0001
    refute Levenshtein.far_apart?(a, b)
    assert_in_delta 0.8, Levenshtein.similarity_at_least(a, b), 0.0001
  end

  test "similarity_at_least はしきい値に届けば類似度・届かなければ nil" do
    assert_in_delta 1.0, Levenshtein.similarity_at_least("サツジン", "サツジン"), 0.0001
    # 距離1 / 長さ10 → 0.9(届く)
    assert_in_delta 0.9, Levenshtein.similarity_at_least("アイウエオカキクケコ", "アイウエオカキクケソ"), 0.0001
    # 距離1 / 長さ4 → 0.75(届かない)
    assert_nil Levenshtein.similarity_at_least("サツジン", "サツジソ")
    assert_nil Levenshtein.similarity_at_least("サツジンジケン", "カレー")
  end

  test "similarity_at_least は空文字列を扱える" do
    assert_in_delta 1.0, Levenshtein.similarity_at_least("", ""), 0.0001
    assert_nil Levenshtein.similarity_at_least("", "アイウエオ")
    assert_nil Levenshtein.similarity_at_least("アイウエオ", "")
  end

  test "similarity_at_least はしきい値を変えられる" do
    # 距離1 / 長さ4 → 0.75。しきい値 0.7 なら届く
    assert_nil Levenshtein.similarity_at_least("サツジン", "サツジソ", 0.8)
    assert_in_delta 0.75, Levenshtein.similarity_at_least("サツジン", "サツジソ", 0.7), 0.0001
  end

  test "distance_within は max 以下なら距離・超えるなら nil" do
    assert_equal 0, Levenshtein.distance_within("サツジン", "サツジン", 0)
    assert_equal 3, Levenshtein.distance_within("kitten", "sitting", 3)
    assert_nil Levenshtein.distance_within("kitten", "sitting", 2)
    assert_equal 3, Levenshtein.distance_within("kitten", "sitting", 5)
    # 文字数差だけで max を超える組は DP に入らず nil
    assert_nil Levenshtein.distance_within("アイウエオ", "ア", 2)
  end

  test "distance_within は片方が空でも扱える" do
    assert_equal 3, Levenshtein.distance_within("", "アイウ", 3)
    assert_nil Levenshtein.distance_within("", "アイウ", 2)
    assert_equal 0, Levenshtein.distance_within("", "", 0)
  end

  test "打ち切り版は距離を最後まで計算した結果と一致する" do
    # 帯状化・早期打ち切りの実装が素朴な DP とずれていないことを、
    # しきい値近傍を厚く踏むランダム生成で確認する。
    chars = "アイウエオカキクケコガギグザジズ".chars
    rng = Random.new(20260811)

    2_000.times do
      a = Array.new(rng.rand(0..12)) { chars.sample(random: rng) }.join
      b = if rng.rand < 0.6
        broken = a.dup
        rng.rand(0..3).times do
          next if broken.empty?
          case rng.rand(3)
          when 0 then broken[rng.rand(broken.length)] = chars.sample(random: rng)
          when 1 then broken.insert(rng.rand(broken.length + 1), chars.sample(random: rng))
          else        broken.slice!(rng.rand(broken.length))
          end
        end
        broken
      else
        Array.new(rng.rand(0..12)) { chars.sample(random: rng) }.join
      end

      truth = Levenshtein.similarity(a, b)
      actual = Levenshtein.similarity_at_least(a, b)
      message = "a=#{a.inspect} b=#{b.inspect} 距離=#{Levenshtein.distance(a, b)}"
      if truth >= Levenshtein::SIMILARITY_THRESHOLD
        assert_equal truth, actual, message
      else
        assert_nil actual, message
      end

      max = rng.rand(0..4)
      distance = Levenshtein.distance(a, b)
      within = Levenshtein.distance_within(a, b, max)
      message = "a=#{a.inspect} b=#{b.inspect} max=#{max}"
      if distance <= max
        assert_equal distance, within, message
      else
        assert_nil within, message
      end
    end
  end

  test "far_apart? はしきい値を満たす組を決して弾かない" do
    chars = "アイウエオカキクケコ".chars
    rng = Random.new(4321)

    2_000.times do
      a = Array.new(rng.rand(0..12)) { chars.sample(random: rng) }.join
      b = Array.new(rng.rand(0..12)) { chars.sample(random: rng) }.join
      next unless Levenshtein.far_apart?(a, b)

      assert Levenshtein.similarity(a, b) < Levenshtein::SIMILARITY_THRESHOLD,
             "far_apart? が似ている組を弾いた: a=#{a.inspect} b=#{b.inspect}"
    end
  end

  test "分割済み版は文字列版と同じ結果を返す" do
    a = "アイウエオカキクケコ"
    b = "アイウエオカキクケソ"
    assert_equal Levenshtein.similarity_at_least(a, b), Levenshtein.similarity_at_least_chars(a.chars, b.chars)
    assert_equal Levenshtein.distance_within(a, b, 2), Levenshtein.distance_within_chars(a.chars, b.chars, 2)
    assert_nil Levenshtein.similarity_at_least_chars("サツジン".chars, "カレー".chars)
  end
end
