require "test_helper"

# 単語の共有カード(og:image)の配信。カードの中身は WordShareCardTest、焼き方は ShareCardRendererTest。
class Words::ShareCardsControllerTest < ActionDispatch::IntegrationTest
  test "焼けたカードを PNG で返し、今の版の URL だけを長く持たせる" do
    word = words(:abc_murder)
    renderer = Object.new
    renderer.define_singleton_method(:fetch) { |**| ShareCardRenderer::PNG_SIGNATURE }

    stub_method(ShareCardRenderer, :available?, -> { true }) do
      stub_method(ShareCardRenderer, :new, -> { renderer }) do
        get word_share_card_path(word, format: :png, v: WordShareCard.new(word).digest)
        assert_response :success
        assert_equal "image/png", response.media_type
        assert_equal ShareCardRenderer::PNG_SIGNATURE, response.body.b
        assert_match(/\Ainline/, response.headers["Content-Disposition"])
        assert_includes response.headers["Cache-Control"], "public"
        assert_includes response.headers["Cache-Control"], "immutable"
        # 共有キャッシュ(Cloudflare など)に載せられるよう、Cookie を発行しない
        assert_nil response.headers["Set-Cookie"]

        get word_share_card_path(word, format: :png, v: "old")
        assert_response :success
        assert_not_includes response.headers["Cache-Control"], "immutable"
      end
    end
  end

  test "焼けない環境では既定のカードへ回し、未公開の語は 404 にする" do
    stub_method(ShareCardRenderer, :available?, -> { false }) do
      get word_share_card_path(words(:abc_murder), format: :png)
      assert_redirected_to "/og-default.png"

      get word_share_card_path(words(:pending_haruhi), format: :png)
      assert_response :not_found
    end
  end
end
