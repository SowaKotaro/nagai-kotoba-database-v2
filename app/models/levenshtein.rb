# 2つの文字列の編集距離(Levenshtein 距離)と、正規化した類似度を計算する値オブジェクト。
# 読みの重複・類似チェック(一括登録・公開の収録リクエスト)で使う。純 Ruby 実装で gem を増やさない。
module Levenshtein
  # 「似ている」とみなす正規化類似度のしきい値。管理側の一括登録(step3)と
  # 公開側の収録リクエスト(Issue 75)で同じ基準を使うため、ここを単一の正とする。
  SIMILARITY_THRESHOLD = 0.8

  module_function

  # 挿入・削除・置換の最小回数(編集距離)を返す。
  # 文字単位で比較する(日本語の読み=かなを想定)。
  def distance(a, b)
    a = a.to_s
    b = b.to_s
    return b.length if a.empty?
    return a.length if b.empty?

    a_chars = a.chars
    b_chars = b.chars
    # 直前の行だけ保持して O(min) メモリで計算する。
    previous = (0..b_chars.length).to_a

    a_chars.each_with_index do |a_char, i|
      current = [ i + 1 ]
      b_chars.each_with_index do |b_char, j|
        cost = a_char == b_char ? 0 : 1
        current << [
          current[j] + 1,        # 挿入
          previous[j + 1] + 1,   # 削除
          previous[j] + cost     # 置換(一致なら据え置き)
        ].min
      end
      previous = current
    end

    previous.last
  end

  # 正規化した類似度(0.0〜1.0)。1.0 が完全一致。
  # 距離を「長い方の文字数」で割って正規化するため、長さの違う読みも公平に比較できる。
  def similarity(a, b)
    a = a.to_s
    b = b.to_s
    longest = [ a.length, b.length ].max
    return 1.0 if longest.zero? # 両方空なら一致扱い

    1.0 - (distance(a, b).to_f / longest)
  end

  # しきい値に届く可能性が無い組を、距離計算の前に安価に弾く。
  # 編集距離は最低でも文字数の差だけかかるため、|差| が許容距離を超えていれば、
  # 距離を計算するまでもなく類似度はしきい値未満で確定する。
  def far_apart?(a, b, threshold = SIMILARITY_THRESHOLD)
    a_length = a.to_s.length
    b_length = b.to_s.length
    longest = [ a_length, b_length ].max
    return false if longest.zero?

    (a_length - b_length).abs > max_distance_for(longest, threshold)
  end

  # しきい値を満たしうる編集距離の上限。
  #
  # ceil で緩めに取るのが要点。(1 - 0.8) は倍精度で 0.19999999999999996 になるため、
  # 素直に (1 - threshold) * longest と書くと、読み10字・距離2(類似度ちょうど 0.8)
  # のような「しきい値ぴったり」の組を枝刈りで取りこぼす。収録語は読み10文字以上
  # ばかりなので、この取りこぼしは実データで頻繁に起きる。
  # 緩めに通したうえで、最終判定は #similarity と同じ浮動小数の比較に委ねる。
  def max_distance_for(longest, threshold = SIMILARITY_THRESHOLD)
    ((1 - threshold) * longest).ceil
  end

  # 類似度がしきい値に届く場合だけその値を返し、届かなければ nil を返す。
  #
  # しきい値があると許容できる編集距離はごく小さい(0.8 で13字なら距離2まで)。
  # #similarity は届かないと分かった後も距離を最後まで計算するが、こちらは
  # #distance_within の打ち切りで途中で切り上げる。総当たり照合(一括登録の
  # 重複チェック・公開の収録リクエスト)はこのメソッドを使うこと。
  def similarity_at_least(a, b, threshold = SIMILARITY_THRESHOLD)
    similarity_at_least_chars(a.to_s.chars, b.to_s.chars, threshold)
  end

  # #similarity_at_least の、文字列を分割済みで受け取る版。
  #
  # 総当たり照合では同じ候補を何度も突き合わせるため、String#chars を毎回呼ぶと
  # それ自体が支配的なコストになる(実測で1組あたり約4µs)。ループの外で一度だけ
  # 分割し、内側ではこちらを使うこと。
  def similarity_at_least_chars(a_chars, b_chars, threshold = SIMILARITY_THRESHOLD)
    longest = a_chars.length > b_chars.length ? a_chars.length : b_chars.length
    return 1.0 if longest.zero?

    distance = distance_within_chars(a_chars, b_chars, max_distance_for(longest, threshold))
    return nil unless distance

    similarity = 1.0 - (distance.to_f / longest)
    similarity >= threshold ? similarity : nil
  end

  # 編集距離が max 以下ならその距離を、max を超えると確定した時点で nil を返す。
  def distance_within(a, b, max)
    distance_within_chars(a.to_s.chars, b.to_s.chars, max)
  end

  # #distance_within の、文字列を分割済みで受け取る版。
  #
  # 距離が max を超えられないということは、DP 表の対角から max より離れたセルは
  # 通らないということなので、帯の中だけを埋める(Ukkonen の帯状化)。さらに
  # 行の最小値は行が進んでも下がらないため、行全体が max を超えたら打ち切れる。
  # 行の配列は2本を使い回し、行ごとの確保をしない。
  def distance_within_chars(a_chars, b_chars, max)
    a_length = a_chars.length
    b_length = b_chars.length
    return nil if (a_length - b_length).abs > max
    return b_length <= max ? b_length : nil if a_length.zero?
    return a_length <= max ? a_length : nil if b_length.zero?

    over = max + 1 # max 超えを表す番兵。これ以上は正確な値を持つ必要がない
    previous = Array.new(b_length + 1) { |j| j > max ? over : j }
    current = Array.new(b_length + 1, over)

    i = 0
    while i < a_length
      a_char = a_chars[i]
      current.fill(over)
      current[0] = i + 1 > max ? over : i + 1
      row_min = current[0]
      # 対角(j = i+1)から max より離れたセルは、どう進んでも max を超える。
      lower = i + 1 - max
      lower = 1 if lower < 1
      upper = i + 1 + max
      upper = b_length if upper > b_length

      j = lower
      while j <= upper
        value = previous[j - 1] + (a_char == b_chars[j - 1] ? 0 : 1) # 置換(一致なら据え置き)
        insertion = current[j - 1] + 1
        value = insertion if insertion < value
        deletion = previous[j] + 1
        value = deletion if deletion < value
        value = over if value > max
        current[j] = value
        row_min = value if value < row_min
        j += 1
      end

      return nil if row_min > max

      previous, current = current, previous
      i += 1
    end

    previous[b_length] > max ? nil : previous[b_length]
  end
end
