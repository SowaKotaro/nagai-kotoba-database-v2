# 登録予定単語をローカルの調査スキルへ渡すための書き出し(expand・notation の段の画面)。
#
# スキルは表記を変えたり語を増やしたりするので、取り込み時に表層形では対応が付かない。
# そこで各行を「#ID 表層形」にし、スキルに ID をそのまま JSON で返させる。
class WordCandidateExport
  # 段 => 渡す先(スキルのコマンド・入力ファイル・取り込む出力ファイル)。
  TARGETS = {
    "expand" => { command: "/expand", input: "research/inputs/expansion.txt", output: "research/outputs/expansion.json",
                  imported_at: :expanded_at },
    "notation" => { command: "/notation", input: "research/inputs/notation.txt", output: "research/outputs/notation.json",
                    imported_at: :notated_at }
  }.freeze

  attr_reader :step

  def initialize(step)
    @step = step.to_s
  end

  def target = TARGETS.fetch(@step)

  # まだ結果を取り込んでいない、その段の語(expand で増えた語は expanded_at が立っているので含まない)。
  def candidates
    @candidates ||= WordCandidate.where(status: @step, target[:imported_at] => nil).in_tree_order.to_a
  end

  def text
    candidates.map { |candidate| "##{candidate.id} #{candidate.surface}" }.join("\n")
  end
end
