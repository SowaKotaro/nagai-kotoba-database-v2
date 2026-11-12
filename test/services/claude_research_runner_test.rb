require "test_helper"

# claude 本体は呼ばない(利用枠を使い、結果も揺れる)。起動・時間切れ・起動できないときの扱いだけを、代わりのスクリプトで見る。
class ClaudeResearchRunnerTest < ActiveSupport::TestCase
  test "引数を配列のまま渡して終了コードを返し、時間切れと起動できないときは false にしてログに残す" do
    Dir.mktmpdir do |dir|
      dir = Pathname(dir)
      log = dir.join("claude.log")
      fake = ->(body) { dir.join("fake").tap { |path| path.write("#!/bin/sh\n#{body}\n") && path.chmod(0o755) } }

      # 引数はシェルを通らずに届く(プロンプトの空白・記号もそのまま)。Bash と公開語の写しの Read は禁じる
      assert ClaudeResearchRunner.new(command: fake.call('printf "%s\n" "$@"').to_s).call("/notation a b; rm -rf x", log_path: log)
      args = log.readlines(chomp: true)
      assert_equal [ "-p", "/notation a b; rm -rf x", "--model", "default" ], args.first(4)
      assert_equal [ "--disallowedTools", "Bash", "Read(research/auto/corpus/**)" ], args.last(3)
      assert_not_includes args[args.index("--allowedTools") + 1].split(","), "Bash"

      assert_not ClaudeResearchRunner.new(command: fake.call("exit 1").to_s).call("/reading", log_path: log)

      assert_not ClaudeResearchRunner.new(command: fake.call("sleep 5").to_s, timeout: 0.2).call("/reading", log_path: log)
      assert_includes log.read, "0.2 秒で打ち切りました"

      assert_not ClaudeResearchRunner.new(command: dir.join("no-such-claude").to_s).call("/reading", log_path: log)
      assert_includes log.read, "Errno::ENOENT"
    end
  end
end
