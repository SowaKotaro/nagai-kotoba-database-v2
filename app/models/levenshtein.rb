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
  # 編集距離は最低でも文字数の差だけかかるため、|差| が (1-しきい値)×長い方 を
  # 超えていれば、距離を計算するまでもなく類似度はしきい値未満で確定する。
  def far_apart?(a, b, threshold = SIMILARITY_THRESHOLD)
    a_length = a.to_s.length
    b_length = b.to_s.length
    longest = [ a_length, b_length ].max
    return false if longest.zero?

    (a_length - b_length).abs > (1 - threshold) * longest
  end
end
