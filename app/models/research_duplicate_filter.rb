# 調査の自動実行(ResearchRun)で、調べる前・調べた後の語から重複を落とすふるい。
# 本番の画面が担う 2 つの照合を、ローカルの語の一覧に対して行う:
# - 表層形: 登録予定単語の照合(WordCandidateDuplicateCheck.key)で畳んで、完全に一致したら重複
# - 読み: 一括登録 step3 と同じ Levenshtein::SIMILARITY_THRESHOLD 以上なら重複
# 照合の相手は、公開済みの語の写し(ResearchCorpus)・過去の run の台帳(ResearchLedger)・同じ run で先に通した語。
# 自動実行では警告ではなく却下に使うので、同じ系統の兄弟(読みが似る)も落ちる。これはオーナー判断で許容している。
# 種別: 値オブジェクト（DB に触れない）。
class ResearchDuplicateFilter
  # 一致した相手(理由の文に使う)。
  Match = Data.define(:kind, :surface, :reading)

  # known は [表層形, 読み or nil] の配列(照合の相手)。
  def initialize(known = [])
    @keys = {}
    @readings = []
    known.each { |surface, reading| remember(surface, reading) }
  end

  # 一致した相手を 1 件返す。無ければ nil。表層形の一致を先に見る。
  def match(surface, reading)
    key = WordCandidateDuplicateCheck.key(surface)
    return Match.new(kind: :surface, surface: @keys[key], reading: nil) if key.present? && @keys.key?(key)
    return nil if reading.blank?

    chars = reading.chars
    hit = @readings.find { |_surface, _reading, known_chars| Levenshtein.similarity_at_least_chars(chars, known_chars) }
    hit && Match.new(kind: :reading, surface: hit[0], reading: hit[1])
  end

  # 照合を通した語を、以降の照合の相手に足す(同じ run の中で先に来た語を正とする)。
  def remember(surface, reading)
    key = WordCandidateDuplicateCheck.key(surface)
    @keys[key] ||= surface if key.present?
    @readings << [ surface, reading, reading.chars ] if reading.present?
  end
end
