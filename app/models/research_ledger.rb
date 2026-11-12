# 調査の自動実行(ResearchPipeline)の台帳。run をまたいで「一度扱った語」を覚えておく TSV。
# 本番の登録予定単語が不要にした語を残して再流入を防ぐのと同じ役目を、ローカルで持つ
# (自動実行は本番に書き込まないので、本番の候補の一覧には載らない)。
#
# 行: 記録日 / run / 種類(seed=使った種語・word=調べた語) / 結果(output=登録用に出した・rejected=却下) / 段 / 表層形 / 読み / 理由
# 1 語は、却下された段か、登録用に出した時点で 1 行になる。追記だけで、書き換えない。
# 種別: 調査 JSON の入出力。
class ResearchLedger
  Row = Data.define(:recorded_on, :run_id, :kind, :outcome, :stage, :surface, :reading, :reason)
  COLUMNS = Row.members

  def initialize(path)
    @path = Pathname(path)
  end

  def rows
    return [] unless @path.exist?

    @path.each_line(chomp: true).filter_map do |line|
      values = line.split("\t", -1)
      Row.new(**COLUMNS.zip(values.map(&:presence)).to_h) if values.size == COLUMNS.size
    end
  end

  # 照合の相手([表層形, 読み])。種語の行は含めない(種語は /expand の出力に自身も並ぶので、
  # 含めると自分の run で自分に当たる。種語も語として調べた時点で word の行になる)。
  # except_run の行は除く(その run 自身の照合は run の中で行う)。
  def known_words(except_run: nil)
    rows.select { |row| row.kind == "word" && row.run_id != except_run }.map { |row| [ row.surface, row.reading ] }
  end

  # 使った種語の表層形。
  def used_seeds
    rows.select { |row| row.kind == "seed" }.to_set(&:surface)
  end

  def append(rows)
    return if rows.empty?

    FileUtils.mkdir_p(@path.dirname)
    @path.open("a") do |file|
      rows.each { |row| file.puts(COLUMNS.map { |column| row.public_send(column).to_s.tr("\t\n", "  ") }.join("\t")) }
    end
  end
end
