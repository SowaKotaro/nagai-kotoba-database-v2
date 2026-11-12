# 調査スキルを Claude Code のヘッドレス実行(claude -p)で 1 段ぶん回すラッパー。調査の自動実行(ResearchPipeline)が使う。
# 本番では使わない(ローカルの cron から rake research:auto で動く)。
#
# 渡すツールは /harvest の cron と同じ(Web で調べてファイルに書くだけ)。Bash は渡さない:
# 読みの文字数と重複の照合はスキルの外のコード(ResearchRun)が行うので要らない。
# 公開語の写し(research/auto/corpus)は百万字を超えるので、誤って読まないよう Read も禁じる。
#
# セキュリティ: コマンドは配列で渡してシェルを通さない。
# 失敗(起動できない・時間切れ・異常終了)は false を返し、呼び出し側は段の失敗として数える。
# 出力の良し悪しはここでは見ない(利用上限で途中終了しても 0 で終わることがあるので、ResearchRun が中身で確かめる)。
# 種別: 外部コマンドのラッパー（app/services には外部プロセスを起動するクラスだけを置く）。
class ClaudeResearchRunner
  COMMAND = "claude".freeze
  ALLOWED_TOOLS = "Skill,ToolSearch,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch".freeze
  DISALLOWED_TOOLS = [ "Bash", "Read(research/auto/corpus/**)" ].freeze
  # 秒。1 段(種語 5 の /expand、その後の数十〜百数十語の /notation・/reading)が収まる長さ。
  TIMEOUT = 3 * 60 * 60

  def initialize(command: COMMAND, timeout: TIMEOUT)
    @command = command
    @timeout = timeout
  end

  # prompt(例 "/notation research/auto/runs/…/input.txt --out …")を実行し、標準出力と標準エラーを log_path に書く。
  def call(prompt, log_path:)
    command = [ @command, "-p", prompt, "--model", "default", "--allowedTools", ALLOWED_TOOLS,
                "--disallowedTools", *DISALLOWED_TOOLS ]
    pid = Process.spawn(*command, chdir: Rails.root.to_s, in: File::NULL, out: log_path.to_s, err: [ :child, :out ])
    waiter = Process.detach(pid)
    return waiter.value.success? if waiter.join(@timeout)

    kill(pid)
    waiter.join
    File.write(log_path, "\n[ClaudeResearchRunner] #{@timeout} 秒で打ち切りました\n", mode: "a")
    false
  rescue SystemCallError => error
    File.write(log_path, "[ClaudeResearchRunner] #{error.class}: #{error.message}\n", mode: "a")
    false
  end

  private

  def kill(pid)
    Process.kill(:TERM, pid)
  rescue Errno::ESRCH
    nil # 打ち切る前に終わっていた
  end
end
