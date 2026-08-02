require "test_helper"

# 管理側の収録リクエスト確認(Issue 75)。認可と、一括操作(状態変更・一括登録への受け渡し・削除)。
class Admin::WordRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @request_record = WordRequest.create!(
      ip_address: "203.0.113.10", user_agent: "TestAgent/1.0",
      referer: "http://www.example.com/words", origin_path: "/words?q=%E8%AA%9E",
      items_attributes: {
        "0" => { surface: "リクエストされた言葉", reading: "リクエストサレタコトバ" },
        "1" => { surface: words(:abc_murder).surface, reading: "エービーシーサツジンジケン" }
      }
    )
    @item = @request_record.items.first
  end

  test "未ログインでは一覧を見られない" do
    get admin_requests_path
    assert_redirected_to new_session_path
  end

  test "ログインすれば一覧を見られる" do
    sign_in_as(admins(:one))
    get admin_requests_path
    assert_response :success
    assert_select "td", text: /リクエストされた言葉/
  end

  test "投稿後に収録された語には印が付く" do
    sign_in_as(admins(:one))
    get admin_requests_path
    # fixtures の公開語と同じ表層形のリクエストには「収録済み」を出す。
    assert_select ".admin-requests-table__registered"
  end

  test "状態で絞り込める" do
    sign_in_as(admins(:one))
    @item.update!(status: :rejected)

    get admin_requests_path(status: "rejected")
    assert_response :success
    assert_select "tbody tr", 1
  end

  test "同じ IP のリクエストだけを見られる" do
    sign_in_as(admins(:one))
    other = WordRequest.create!(ip_address: "198.51.100.1",
                                items_attributes: { "0" => { surface: "別の人からの言葉" } })

    get admin_requests_path(ip: other.ip_address)
    assert_select "tbody tr", 1
  end

  test "選択した語の状態をまとめて更新する" do
    sign_in_as(admins(:one))
    post bulk_admin_requests_path,
         params: { item_ids: @request_record.items.map(&:id), commit: "apply",
                   status_to: "accepted", admin_memo: "採用" }

    assert_redirected_to admin_requests_path
    @request_record.items.each do |item|
      item.reload
      assert item.accepted?
      assert_equal "採用", item.admin_memo
      # 未着手から動かした時刻が残る。
      assert_predicate item.handled_at, :present?
    end
  end

  test "状態を選ばずに適用したら知らせる" do
    sign_in_as(admins(:one))
    post bulk_admin_requests_path, params: { item_ids: [ @item.id ], commit: "apply" }
    assert_equal I18n.t("admin.word_requests.bulk.no_status"), flash[:alert]
    assert_predicate @item.reload, :pending?
  end

  test "選択が無ければ知らせる" do
    sign_in_as(admins(:one))
    post bulk_admin_requests_path, params: { commit: "apply", status_to: "accepted" }
    assert_equal I18n.t("admin.word_requests.bulk.no_selection"), flash[:alert]
  end

  test "選択した語を一括登録の step1 へ渡す" do
    sign_in_as(admins(:one))
    post bulk_admin_requests_path, params: { item_ids: @request_record.items.map(&:id), commit: "to_bulk" }

    assert_redirected_to new_admin_word_path(text: @request_record.items.map(&:surface).join("\n"))
    follow_redirect!
    # 箇条書き欄に流し込まれている。
    assert_select "textarea", text: /リクエストされた言葉/
  end

  test "選択した語を削除できる" do
    sign_in_as(admins(:one))
    assert_difference "WordRequestItem.count", -1 do
      post bulk_admin_requests_path, params: { item_ids: [ @item.id ], commit: "destroy" }
    end
  end

  test "未着手の件数を管理ナビに出す" do
    sign_in_as(admins(:one))
    get admin_requests_path
    assert_select ".admin-nav__badge", text: WordRequestItem.pending.count.to_s
  end
end
