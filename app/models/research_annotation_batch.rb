# 調査の自動実行で回す /annotation の 1 回ぶん。人が管理画面の「調査用データの書き出し」を
# research/auto/inbox/annotation.json に置くと、司令塔(ResearchPipeline)がディレクトリへ移して /annotation に渡す。
# 結果の annotation.json は、人が「提案 JSON の取り込み」に貼る(本番への書き込みは人が行う)。
#
#   input.json   書き出し(inbox から移したもの)
#   annotation.json  /annotation の提案 JSON(既定の research/outputs/ と同じ名前)
#   attempts     失敗の回数(ResearchRun::MAX_ATTEMPTS に届いたら諦める)
# 種別: 調査 JSON の入出力。
class ResearchAnnotationBatch
  attr_reader :directory

  # inbox の書き出しを新しいディレクトリへ移す。
  def self.receive(inbox_path, root)
    directory = ResearchRun.new_directory(root)
    FileUtils.mv(inbox_path, directory.join("input.json"))
    new(directory)
  end

  # まだ結果の出ていない回(古い順)。
  def self.pending(root)
    Pathname(root).glob("*/input.json").sort.map { |path| new(path.dirname) }.reject { |batch| batch.done? || batch.given_up? }
  end

  def initialize(directory)
    @directory = Pathname(directory)
  end

  def input_path = directory.join("input.json")
  def output_path = directory.join("annotation.json")
  def log_path = directory.join("claude.log")
  def done? = output_path.exist? && valid?(output_path.read)
  def attempts = directory.join("attempts").exist? ? directory.join("attempts").read.to_i : 0
  def given_up? = attempts >= ResearchRun::MAX_ATTEMPTS

  def record_failure
    directory.join("attempts").write("#{attempts + 1}\n")
  end

  # 提案 JSON が読め、書き出しの全語(word_id)に提案があるか。
  def valid?(text)
    proposals = ResearchJson.array_at(text, "proposals")
    words = ResearchJson.array_at(input_path.read, "words")
    return false unless proposals && words

    (words.map { |word| word["word_id"].to_i } - proposals.map { |proposal| proposal["word_id"].to_i }).empty?
  end
end
