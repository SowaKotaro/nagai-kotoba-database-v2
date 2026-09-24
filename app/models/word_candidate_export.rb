# 登録予定単語をローカルの調査スキルへ渡すための書き出し(拡張・表記・登録待ちの画面)。
#
# /expand・/notation は表記を変えたり語を増やしたりするので、取り込み時に表層形では対応が付かない。
# そこで各行を「#ID 表層形」にし、スキルに ID をそのまま JSON で返させる。
# /reading は一括登録の画面で表層形のまま突き合わせるので、表層形だけを書き出す。
class WordCandidateExport
  # 段 => 渡す語のステータスと、渡す先(スキルのコマンド・入力ファイル・取り込む出力ファイル)。
  TARGETS = {
    "expand" => { status: "expanding", command: "/expand", with_ids: true,
                  input: "research/inputs/expansion.txt", output: "research/outputs/expansion.json" },
    "notation" => { status: "notating", command: "/notation", with_ids: true,
                    input: "research/inputs/notation.txt", output: "research/outputs/notation.json" },
    "reading" => { status: "ready", command: "/reading", with_ids: false,
                   input: "research/inputs/reading.txt", output: "research/outputs/reading.json" }
  }.freeze

  attr_reader :step

  def initialize(step)
    @step = step.to_s
  end

  def target = TARGETS.fetch(@step)

  # その段でスキルの結果を待っている語。
  def candidates
    @candidates ||= WordCandidate.where(status: target[:status]).in_tree_order.to_a
  end

  def text
    candidates.map { |candidate| target[:with_ids] ? "##{candidate.id} #{candidate.surface}" : candidate.surface }.join("\n")
  end
end
