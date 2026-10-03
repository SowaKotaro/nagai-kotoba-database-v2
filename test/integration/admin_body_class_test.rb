require "test_helper"

# 管理画面のトーン(admin.css)は <body class="is-admin"> の下でだけ効く。
# 付けるかどうかは AdminHelper#admin_page?(管理画面のコントローラか)で決める(layouts/application.html.erb)。
class AdminBodyClassTest < ActionDispatch::IntegrationTest
  test "管理画面では body に is-admin が付き、公開ページとログイン画面には付かない" do
    get new_session_path
    assert_select "body.is-admin", 0

    sign_in_as(Admin.take)
    [ admin_root_path, admin_words_path, admin_tags_path ].each do |path|
      get path
      assert_select "body.is-admin", { count: 1 }, path
    end

    # ログインしていても、公開ページには付けない
    [ root_path, words_path, word_path(words(:abc_murder)), about_path ].each do |path|
      get path
      assert_select "body", { count: 1 }, path
      assert_select "body.is-admin", { count: 0 }, path
    end
  end
end
