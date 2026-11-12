# 調査の自動実行(ResearchPipeline)が重複照合に使う、公開済みの語の写し。
# 元は公開側の llms-full.txt(LlmsController#full)で、司令塔が取得してローカルに置く。
# AI には読ませず、コードだけが読む(全文は百万字を超え、コンテキストに流すとスケールしない)。
#
# llms-full.txt は LLM 向けの文書で、機械で読む約束は無い。重複照合に要る「見出し語(### 表層形)」と
# 「- 読み: カタカナ(N字 …)」の 2 種類の行だけを拾う。書式が変わったら気づけるよう、
# 冒頭の「公開している全 N 語」と見出しの数が合わなければ読めなかった扱い(nil)にする。
# 種別: 調査 JSON の入出力。
class ResearchCorpus
  # 1 語ぶん。readings は語義ごとの読み(同音異義・多義なら複数)。
  Entry = Data.define(:surface, :readings)

  WORD_COUNT_LINE = /公開している全 (\d+) 語/
  HEADING_LINE = /\A### (.+)\z/
  READING_LINE = /\A- 読み: ([^(]+)\(/

  # 本文を読んで Entry の配列を返す。見出しの数が冒頭の語数と合わなければ nil。
  def self.parse(text)
    declared = text.to_s[WORD_COUNT_LINE, 1]&.to_i
    return nil unless declared

    entries = []
    text.each_line(chomp: true) do |line|
      if (surface = line[HEADING_LINE, 1])
        entries << Entry.new(surface: surface.strip, readings: [])
      elsif (reading = line[READING_LINE, 1]) && entries.any?
        entries.last.readings << reading.strip
      end
    end
    entries.size == declared ? entries : nil
  end

  # ファイルを読む。無い・読めない・書式が合わなければ nil。
  def self.load(path)
    path = Pathname(path)
    path.exist? ? parse(path.read) : nil
  end
end
