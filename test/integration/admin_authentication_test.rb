require "test_helper"

# 管理配下(admin/)の全アクションは、未ログインならログイン画面へ送り、何も変えない。
# ルート表から列挙して全数を確かめるので、管理アクションを足したときに書き忘れようがない
# (各コントローラのテストには未ログインの検証を書かない。Issue 96)。
class AdminAuthenticationTest < ActionDispatch::IntegrationTest
  # 動的セグメントの埋め方。認証は before_action で先に弾くので、実在する値でさえあればよい。
  SEGMENT_VALUES = { kind: "entity_types" }.freeze

  test "管理配下の全アクションは未ログインだとログイン画面へ送り、データを変えない" do
    routes = admin_routes
    assert_operator routes.size, :>=, 40, "管理ルートの列挙が空振りしている"

    routes.each do |verb, path|
      assert_no_changes -> { table_snapshot }, "#{verb} #{path} がデータを変えた" do
        process verb.downcase.to_sym, path
      end
      assert_redirected_to new_session_path, "#{verb} #{path} が未ログインで通っている"
    end
  end

  private

  def admin_routes
    Rails.application.routes.routes.filter_map do |route|
      next unless route.defaults[:controller].to_s.start_with?("admin/")

      route.verb.split("|").map { |verb| [ verb, fill_segments(route.path.spec.to_s.delete_suffix("(.:format)")) ] }
    end.flatten(1).uniq
  end

  def fill_segments(path)
    path.gsub(/:(\w+)/) { SEGMENT_VALUES.fetch(Regexp.last_match(1).to_sym) { words(:pending_haruhi).id.to_s } }
  end

  # 全テーブルの件数と最終更新(書き換えだけの操作も拾う)
  def table_snapshot
    connection = ActiveRecord::Base.connection
    connection.tables.index_with do |table|
      columns = connection.columns(table).map(&:name)
      updated = columns.include?("updated_at") ? ", MAX(updated_at)" : ""
      connection.select_rows("SELECT COUNT(*)#{updated} FROM #{connection.quote_table_name(table)}")
    end
  end
end
