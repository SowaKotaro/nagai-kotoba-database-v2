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
    when "annotations", "annotation_decks" then :annotations
    when "tags" then :tags
    when "design_mocks" then :design_mocks
    when "word_requests" then :requests
    when "words"
      ADMIN_REGISTER_ACTIONS.include?(action_name) ? :register : :words
    end
  end

  # 収録リクエスト(Issue 75)の共通ナビのラベル。未着手が溜まっていることに
  # 管理画面へ来たときに気づけるよう、件数をバッジで添える(通知メールは持たない方針)。
  def admin_requests_nav_label
    count = WordRequestItem.pending.count
    label = t("admin.nav.requests")
    return label if count.zero?

    safe_join([ label, tag.span(count, class: "admin-nav__badge") ])
  end

  # 現在地に aria-current="page" を付けた共通ナビのリンク。
  def admin_nav_link(label, path, section)
    options = { class: "admin-nav__link" }
    options["aria-current"] = "page" if admin_nav_current == section
    link_to label, path, options
  end

  # その場追加(ジャンル・語種・品詞・エンティティ)の Stimulus に渡す文言。
  # 追加は JS が DOM を書き換えるため、成否のメッセージも JS 側で出す必要がある。
  # ハードコードせず i18n から一括で渡す(genre-picker / inline-add で共通)。
  def inline_add_labels_json
    t("admin.inline_add.client").to_json
  end

  # 単語一覧のジャンル絞り込みセレクトの選択肢([表示名, id] の配列)。
  # 大→中→小の階層順に、全角空白の字下げで階層が分かるように並べる。
  def admin_genre_filter_options(genres)
    by_parent = genres.group_by(&:parent_id)
    (by_parent[nil] || []).flat_map do |large|
      [ [ large.name, large.id ] ] +
        (by_parent[large.id] || []).flat_map do |medium|
          [ [ "　#{medium.name}", medium.id ] ] +
            (by_parent[medium.id] || []).map { |small| [ "　　#{small.name}", small.id ] }
        end
    end
  end
end
