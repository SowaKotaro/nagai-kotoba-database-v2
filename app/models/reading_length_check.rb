# 調査スキルが決めた読みが、収録基準の文字数(WordSense::MIN_READING_LENGTH)に届くかの判定。
# /expand の補助スクリプト(.claude/skills/word-expansion-research/reading_length.rb)と、
# 調査の自動実行(ResearchRun)が同じ判定を使う。
#
# 数え方はアプリと同じにする: 読みの正規化は ReadingExtractor#normalize(カタカナと長音符だけを残す)、
# 文字数は word_senses.reading_length(char_length)と同じく 1 文字ずつ数える。
# MeCab の読みは誤りに気づくための参考で、判定を決めるのはスキルの読み。両者で 10 文字の境界をまたぐときだけ「要確認」にする。
# 種別: 値オブジェクト（DB に触れない）。
class ReadingLengthCheck
  # verdict: :ok(基準以上) / :short(基準未満) / :uncertain(MeCab と基準の境界をまたぐ) / :missing(読みが無い)
  Result = Data.define(:verdict, :reading, :length, :mecab_reading, :mecab_length) do
    def ok? = verdict == :ok
  end

  # reading はスキルの読み、mecab_reading は MeCab の読み(無ければ nil)。どちらも正規化してから数える。
  def self.call(reading, mecab_reading = nil)
    own = normalize(reading)
    mecab = normalize(mecab_reading)
    min = WordSense::MIN_READING_LENGTH

    verdict =
      if own.nil? then :missing
      elsif mecab && (own.length >= min) != (mecab.length >= min) then :uncertain
      elsif own.length >= min then :ok
      else :short
      end

    Result.new(verdict:, reading: own, length: own&.length, mecab_reading: mecab, mecab_length: mecab&.length)
  end

  # 正規化の規則は ReadingExtractor#normalize が持つ。ここで定義を複製しない。
  def self.normalize(reading)
    @extractor ||= ReadingExtractor.new
    @extractor.normalize(reading)
  end
end
