# 調査の自動実行(ResearchRun)で、調べる前・調べた後の語から重複を落とすふるい。
# 本番の画面が担う 2 つの照合を、ローカルの語の一覧に対して行う:
# - 表層形: 登録予定単語の照合(WordCandidateDuplicateCheck.key)で畳んで、完全に一致したら重複
# - 読み: 完全に一致したら重複(一括登録 step3 は Levenshtein の類似度で警告するが、ここでは使わない。下記)
# 照合の相手は、公開済みの語の写し(ResearchCorpus)・過去の run の台帳(ResearchLedger)・同じ run で先に通した語。
# 自動実行では警告ではなく却下に使う。類似度では同じ系統の兄弟(読みが似る)まで落ちたので、
# 同じ読みだけを落とす(オーナー判断、2026-11-14)。完全一致ならハッシュで引けて速い。
# 種別: 値オブジェクト（DB に触れない）。
class ResearchDuplicateFilter
  # 一致した相手(理由の文に使う)。
  Match = Data.define(:kind, :surface, :reading)

  # known は [表層形, 読み or nil] の配列(照合の相手)。
  def initialize(known = [])
    @keys = {}
    @readings = {}
    known.each { |surface, reading| remember(surface, reading) }
  end

  # 一致した相手を 1 件返す。無ければ nil。表層形の一致を先に見る。
  def match(surface, reading)
    key = WordCandidateDuplicateCheck.key(surface)
    return Match.new(kind: :surface, surface: @keys[key], reading: nil) if key.present? && @keys.key?(key)
    return nil if reading.blank?

    surface_of_reading = @readings[reading]
    surface_of_reading && Match.new(kind: :reading, surface: surface_of_reading, reading:)
  end

  # 照合を通した語を、以降の照合の相手に足す(同じ run の中で先に来た語を正とする)。
  def remember(surface, reading)
    key = WordCandidateDuplicateCheck.key(surface)
    @keys[key] ||= surface if key.present?
    @readings[reading] ||= surface if reading.present?
  end
end
