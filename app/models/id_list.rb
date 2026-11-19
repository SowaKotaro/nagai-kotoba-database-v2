# 貼り付けた id の並び(「12, 345、678」など)を、正の整数の配列にする。
# Claude Code の調べた結果などから、特定の語をまとめて引くための入力(管理の単語一覧の ids)。
# 区切りは問わず数字の並びだけを拾い、全角の数字も半角に寄せる。重複は落とし、並びは入力の順を保つ。
# 種別: 値オブジェクト（DB に触れない）。
class IdList
  def self.call(text)
    text.to_s.unicode_normalize(:nfkc).scan(/\d+/).map(&:to_i).select(&:positive?).uniq
  end
end
