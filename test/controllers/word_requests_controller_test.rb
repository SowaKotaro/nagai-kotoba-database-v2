require "test_helper"

# 公開側からの収録リクエスト(Issue 75)。
# 閲覧専用だった公開面に開ける唯一の書き込み経路なので、通る経路と弾く経路の両方を押さえる。
# 語数の上限・レートリミットの数え方・重複の判定そのものはモデルのテストで見る。
class WordRequestsControllerTest < ActionDispatch::IntegrationTest
  # 重複チェックの回数はプロセス内のストアに積まれるため、テスト間で持ち越さない。
  setup { WordRequestsController::RATE_LIMIT_STORE.clear }

  # フォーム表示から十分な時間が経った状態の署名トークン(時間トラップを通過する)。
  def valid_token
    travel_to(1.minute.ago) { WordRequestFormToken.issue }
  end

  def submission(items:, token: valid_token, extra: {})
    { word_request: { items_attributes: items }, form_token: token }.merge(extra)
  end

  def one_item(surface: "長い言葉の見本", reading: "ナガイコトバノミホン")
    { "0" => { surface: surface, reading: reading } }
  end

  # 重複チェックはフォームと同じ入力を別 URL へ投げるだけ(トークンもレコードも不要)。
  def check_params(surface:, reading: nil)
    { word_request: { items_attributes: { "0" => { surface: surface, reading: reading }.compact } } }
  end

  test "誰でもフォームを開け、検索結果0件からの導線ではキーワードが埋まり、インデックスはさせない" do
    get new_request_path(surface: "検索して見つからなかった言葉")
    assert_response :success
    assert_select "form[action=?]", requests_path
    assert_select "input[value=?]", "検索して見つからなかった言葉"
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  test "送信すると未着手のリクエストとして保存し、送信の技術メタデータを記録する" do
    assert_difference [ "WordRequest.count", "WordRequestItem.count" ], 1 do
      post requests_path,
           params: submission(items: one_item, extra: { origin_path: "/words?q=%E8%AA%9E" }),
           headers: { "HTTP_USER_AGENT" => "TestAgent/1.0", "HTTP_REFERER" => "http://www.example.com/requests/new" }
    end
    assert_redirected_to new_request_path

    item = WordRequestItem.last
    assert_equal "長い言葉の見本", item.surface
    assert_equal "ナガイコトバノミホン", item.reading
    assert item.pending?

    request_record = WordRequest.last
    assert_predicate request_record.ip_address, :present?
    assert_equal "TestAgent/1.0", request_record.user_agent
    assert_equal "http://www.example.com/requests/new", request_record.referer
    assert_equal "/words?q=%E8%AA%9E", request_record.origin_path
  end

  test "1通で複数語を送れる(メタデータは通側に1回だけ持つ)" do
    items = {
      "0" => { surface: "ひとつめの言葉", reading: "ヒトツメノコトバ" },
      "1" => { surface: "ふたつめの言葉", reading: "フタツメノコトバ" }
    }
    assert_difference "WordRequestItem.count", 2 do
      post requests_path, params: submission(items: items)
    end
    assert_equal 1, WordRequest.count
    assert_equal 2, WordRequest.last.items.size
  end

  test "上限を超える語数や空の送信は受け付けず、入力欄を残す" do
    too_many = (0..WordRequest::MAX_ITEMS).index_with { |i| { surface: "言葉#{i}" } }.transform_keys(&:to_s)
    assert_no_difference "WordRequest.count" do
      post requests_path, params: submission(items: too_many)
    end
    assert_response :unprocessable_entity

    assert_no_difference "WordRequest.count" do
      post requests_path, params: submission(items: { "0" => { surface: "", reading: "" } })
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  # 自動投稿には、手口を知らせないよう成功時と同じ応答を返して黙って捨てる。
  test "ハニーポットが埋まった送信やフォーム表示から速すぎる送信は黙って捨てる" do
    {
      "ハニーポット" => submission(items: one_item, extra: { website: "http://spam.example.com" }),
      "速すぎる送信" => submission(items: one_item, token: WordRequestFormToken.issue)
    }.each do |label, params|
      assert_no_difference "WordRequest.count", label do
        post requests_path, params: params
      end
      assert_redirected_to new_request_path
      assert_equal I18n.t("word_requests.create.created"), flash[:notice], label
    end
  end

  test "署名が不正なトークンは再送を促す" do
    assert_no_difference "WordRequest.count" do
      post requests_path, params: submission(items: one_item, token: "tampered")
    end
    assert_response :unprocessable_entity
    assert_equal I18n.t("word_requests.create.expired"), flash[:alert]
  end

  test "同一 IP から短時間に送りすぎると受け付けない" do
    WordRequest::RATE_LIMITS.min_by(&:last).last.times do
      WordRequest.create!(ip_address: "127.0.0.1", items_attributes: one_item)
    end

    assert_no_difference "WordRequest.count" do
      post requests_path, params: submission(items: one_item)
    end
    assert_response :too_many_requests
  end

  test "重複チェックは収録済み・似ている語・未収録を知らせ、レコードは作らない" do
    assert_no_difference [ "WordRequest.count", "WordRequestItem.count" ] do
      post duplicates_requests_path, params: check_params(surface: words(:abc_murder).surface)
      assert_response :success
      assert_select ".dup-note--exact"

      # 読みだけでも収録済みと分かる(格納はひらがな、入力はカタカナでも DB の as_ci と同じく畳んで一致させる)
      post duplicates_requests_path, params: check_params(surface: "全然ちがう表記", reading: "サツジンジケン")
      assert_select ".dup-note--exact"

      post duplicates_requests_path, params: check_params(surface: "ABC殺人事故")
      assert_select ".dup-note--similar"
      assert_select ".dup-note__link", text: words(:abc_murder).surface

      post duplicates_requests_path, params: check_params(surface: "まだどこにも無いはずの言葉")
      assert_select ".dup-note--none"
      assert_select ".dup-note__verdict", text: I18n.t("word_requests.duplicates.none_title")
    end
  end

  test "重複していても送信は妨げない" do
    assert_difference "WordRequestItem.count", 1 do
      post requests_path, params: submission(items: one_item(surface: words(:abc_murder).surface))
    end
  end

  test "重複チェックの押しすぎは断る" do
    limit = 10
    limit.times { post duplicates_requests_path, params: check_params(surface: "調べたい言葉") }
    assert_response :success

    post duplicates_requests_path, params: check_params(surface: "調べたい言葉")
    assert_response :too_many_requests
    assert_select ".request-table__notice"
  end

  test "受付を止めているときはフォームを出さず、送信も受け付けない" do
    with_requests_disabled do
      get new_request_path
      assert_redirected_to about_path

      assert_no_difference "WordRequest.count" do
        post requests_path, params: submission(items: one_item)
      end
    end
  end

  private

  def with_requests_disabled
    original = Rails.application.config.x.requests_enabled
    Rails.application.config.x.requests_enabled = false
    yield
  ensure
    Rails.application.config.x.requests_enabled = original
  end
end
