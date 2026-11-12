require "test_helper"

# 本番には取りに行かず、file:// の URL で curl を動かす。
class LlmsFullFetcherTest < ActiveSupport::TestCase
  test "読める本文だけで写しを差し替え、読めない本文・取れないときは古い写しのまま :failed を返す" do
    skip "curl が無いため skip" unless system("curl", "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      dir = Pathname(dir)
      source = dir.join("source.txt")
      path = dir.join("corpus/llms-full.txt")
      fetcher = LlmsFullFetcher.new(path, url: "file://#{source}")

      source.write("公開している全 1 語の内容を、1ファイルにまとめています。\n\n### 長い言葉\n- 読み: ナガイコトバ(6字)\n")
      assert_equal :updated, fetcher.call
      assert_equal [ "長い言葉" ], ResearchCorpus.load(path).map(&:surface)

      # 確認画面の HTML など、語数の行が無い本文は写しにしない
      source.write("<html>Just a moment...</html>")
      FileUtils.touch(source, mtime: 1.minute.from_now.to_time)
      assert_equal :failed, fetcher.call
      assert_equal [ "長い言葉" ], ResearchCorpus.load(path).map(&:surface)

      assert_equal :failed, LlmsFullFetcher.new(path, url: "file://#{dir.join("no-such.txt")}").call
      assert_empty dir.join("corpus").glob(".tmp-*"), "一時ファイルを残さない"
    end
  end
end
