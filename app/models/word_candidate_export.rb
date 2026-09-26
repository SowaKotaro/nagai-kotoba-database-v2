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

  # limit を渡すと、待っている語の先頭からその語数だけを書き出す(Claude Code の利用上限に当たらないよう、
  # 数十語ずつスキルに渡すため)。取り込んだ語は待ちから抜けるので、次に書き出すと続きの語が出る。
  def initialize(step, limit: nil)
    @step = step.to_s
    @limit = limit
  end

  def target = TARGETS.fetch(@step)

  # その段でスキルの結果を待っている語(limit があれば先頭からその語数)。
  def candidates
    @candidates ||= waiting.in_tree_order.limit(@limit).to_a
  end

  # その段でスキルの結果を待っている語の総数。
  def total_count
    @total_count ||= @limit ? waiting.count : candidates.size
  end

  # limit のために書き出していない語があるか。
  def limited?
    total_count > candidates.size
  end

  def text
    candidates.map { |candidate| target[:with_ids] ? "##{candidate.id} #{candidate.surface}" : candidate.surface }.join("\n")
  end

  private

  def waiting
    WordCandidate.where(status: target[:status])
  end
end
