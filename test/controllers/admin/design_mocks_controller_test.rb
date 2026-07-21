require "test_helper"

# デザイン案モック。管理者だけが見られる静的ページで、DB には触らない。
class Admin::DesignMocksControllerTest < ActionDispatch::IntegrationTest
  # --- 認可: 未認証は弾く ---
  test "未認証だと一覧はログインへリダイレクト" do
    get admin_design_mocks_path
    assert_redirected_to new_session_path
  end

  test "未認証だとモック本体はログインへリダイレクト" do
    get admin_design_mock_path(style: "measure", page: "home")
    assert_redirected_to new_session_path
  end

  # --- 一覧 ---
  test "認証済みなら一覧が開き、全案・全ページへの導線がある" do
    sign_in_as(Admin.take)
    get admin_design_mocks_path
    assert_response :success

    Admin::DesignMocksHelper::STYLES.each do |style, meta|
      assert_select "h2, p.section-label", text: /#{Regexp.escape(meta[:name])}/
      Admin::DesignMocksHelper::PAGES.each_key do |page|
        assert_select "a[href=?]", admin_design_mock_path(style: style, page: page)
      end
    end
  end

  # --- モック本体: 5案 × 3ページのすべてが描画できる ---
  Admin::DesignMocksHelper::STYLES.each_key do |style|
    Admin::DesignMocksHelper::PAGES.each_key do |page|
      test "#{style}/#{page} が表示できる" do
        sign_in_as(Admin.take)
        get admin_design_mock_path(style: style, page: page)

        assert_response :success
        # 案ごとの専用レイアウト(共通ヘッダー/フッターを持たない)で描画されること
        assert_select "div.dm.dm-#{style}"
        assert_select "header.site-header", false
        assert_select "footer.site-footer", false
        # 既存のデザインシステムを読み込まないこと(治外法権)
        assert_select "link[href*=?]", "application", false
        assert_select "link[href*=?]", "design_mocks"
        # 案・ページを行き来する切替バー
        assert_select ".dm-bar a[href=?]", admin_design_mocks_path
      end
    end
  end

  test "モック本体は DB を読まない" do
    sign_in_as(Admin.take)

    assert_no_queries_on_words do
      get admin_design_mock_path(style: "swiss", page: "ranking")
    end
    assert_response :success
  end

  # --- 未知の案・ページ ---
  test "知らない案は 404" do
    sign_in_as(Admin.take)
    get admin_design_mock_path(style: "bauhaus", page: "home")
    assert_response :not_found
  end

  test "知らないページは 404" do
    sign_in_as(Admin.take)
    get admin_design_mock_path(style: "measure", page: "about")
    assert_response :not_found
  end

  private
    # words / word_senses への SELECT が一度も飛ばないこと(静的モックであることの担保)。
    def assert_no_queries_on_words
      queried = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        queried << payload[:sql] if payload[:sql].match?(/\bwords\b|\bword_senses\b/)
      end
      yield
      assert_empty queried, "モックは単語テーブルを読まない想定"
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
end
