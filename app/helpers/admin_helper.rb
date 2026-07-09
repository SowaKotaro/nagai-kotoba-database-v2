# 管理画面の共通サブナビ(app/views/admin/_nav.html.erb)用ヘルパー(Issue 35)。
module AdminHelper
  # admin/words のうち登録フロー(3ステップ)に属するアクション。
  # それ以外(index/edit/update/destroy)は「単語の管理」扱いにする。
  ADMIN_REGISTER_ACTIONS = %w[new create readings apply_research duplicates].freeze

  # 管理画面(Admin::BaseController 配下)かどうか。レイアウトで共通ナビの表示判定に使う。
  def admin_page?
    controller.is_a?(Admin::BaseController)
  end

  # 共通ナビの現在地(:dashboard / :register / :annotations / :words)。該当なしは nil。
  def admin_nav_current
    case controller_name
    when "dashboard" then :dashboard
    when "annotations" then :annotations
    when "tags" then :tags
    when "words"
      ADMIN_REGISTER_ACTIONS.include?(action_name) ? :register : :words
    end
  end

  # 現在地に aria-current="page" を付けた共通ナビのリンク。
  def admin_nav_link(label, path, section)
    options = { class: "admin-nav__link" }
    options["aria-current"] = "page" if admin_nav_current == section
    link_to label, path, options
  end
end
