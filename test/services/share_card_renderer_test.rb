require "test_helper"

# 共有カードを PNG に焼いて置くサービス。ファイルの扱いは rsvg-convert の代わりのコマンドで確かめ、
# 実際に焼くテストは rsvg-convert と日本語の書体がある環境だけで行う(CI には無いので skip)。
class ShareCardRendererTest < ActiveSupport::TestCase
  # PNG の署名に続けて、渡された SVG をそのまま書き出す(中身は PNG ではないが、置き方の確認には足りる)
  FAKE_COMMAND = [ RbConfig.ruby, "-e", 'STDOUT.binmode; STDOUT.write("\x89PNG\r\n\x1A\n"); STDOUT.write(File.binread(ARGV[0]))' ].freeze

  setup { @directory = Dir.mktmpdir("share_cards") }
  teardown { FileUtils.rm_rf(@directory) }

  test "焼いた PNG を「名前-版.png」に置き、置いてある版は焼き直さずに返す" do
    png = renderer.fetch(name: "word-1", version: "v1", svg: "<svg/>")
    assert png.start_with?(ShareCardRenderer::PNG_SIGNATURE)
    assert_equal [ "word-1-v1.png" ], Dir.children(@directory)

    failing = renderer(command: [ RbConfig.ruby, "-e", "exit 1" ])
    assert_equal png, failing.fetch(name: "word-1", version: "v1", svg: "<svg/>")
  end

  test "新しい版を焼いたら同じ名前の古い版を消し、ほかの名前には触らない" do
    renderer.fetch(name: "word-1", version: "old", svg: "<svg/>")
    renderer.fetch(name: "word-12", version: "old", svg: "<svg/>")
    renderer.fetch(name: "word-1", version: "new", svg: "<svg/>")

    assert_equal %w[word-1-new.png word-12-old.png], Dir.children(@directory).sort
  end

  test "コマンドの失敗・PNG でない出力・時間切れでは nil を返し、書きかけを残さない" do
    {
      "失敗" => [ RbConfig.ruby, "-e", "exit 1" ],
      "PNG でない出力" => [ RbConfig.ruby, "-e", "print 'not png'" ],
      "時間切れ" => [ RbConfig.ruby, "-e", "sleep 5" ]
    }.each do |label, command|
      assert_nil renderer(command:, timeout: 1).fetch(name: "word-1", version: "v1", svg: "<svg/>"), label
      assert_empty Dir.children(@directory), "#{label}: 一時ファイルを残さない"
    end
  end

  test "ほかのリクエストが焼いている最中は待たずに nil を返す(置いてある版はそのまま返す)" do
    cached = renderer.fetch(name: "word-1", version: "v1", svg: "<svg/>")

    ShareCardRenderer::RENDER_LOCK.synchronize do
      assert_nil renderer.fetch(name: "word-2", version: "v1", svg: "<svg/>")
      assert_equal cached, renderer.fetch(name: "word-1", version: "v1", svg: "<svg/>")
    end
    assert_equal [ "word-1-v1.png" ], Dir.children(@directory)

    # 手が空けば焼ける
    assert renderer.fetch(name: "word-2", version: "v1", svg: "<svg/>")
  end

  test "rsvg-convert で 1200×630 の PNG に焼ける" do
    skip "rsvg-convert か日本語の書体が無いため skip" unless ShareCardRenderer.available?

    card = WordShareCard.new(words(:abc_murder))
    png = ShareCardRenderer.new(directory: @directory).fetch(name: "word-1", version: card.digest, svg: card.svg)
    assert_equal [ WordShareCard::WIDTH, WordShareCard::HEIGHT ], png.byteslice(16, 8).unpack("NN") # IHDR の幅と高さ
  end

  private

  def renderer(command: FAKE_COMMAND, timeout: ShareCardRenderer::TIMEOUT)
    ShareCardRenderer.new(directory: @directory, command:, timeout:)
  end
end
