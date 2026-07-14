require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module NagaiKotobaDatabaseV2
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # 日本語アプリのため既定ロケールを日本語にする。
    config.i18n.default_locale = :ja
    config.i18n.available_locales = %i[ja en]

    # canonical / OGP の絶対URLの基点(本番ドメイン。docs/issues.md 確定事項1)。
    # 末尾スラッシュ無し。ENV で上書き可(検証環境・ステージング用)。
    config.x.canonical_host = ENV.fetch("CANONICAL_HOST", "https://nagai-kotoba-database.jp")

    # インデックス解禁スイッチ(Issue 43)。未設定 = 全ページ noindex(公開準備中)。
    # 注釈済み 300〜500 語に達したら本番に INDEXING_ENABLED を設定して解禁する
    # (手順は docs/launch-checklist.md)。テスト環境は解禁後の挙動を既定にする(test.rb)。
    config.x.indexing_enabled = ENV["INDEXING_ENABLED"].present?

    # stylesheet_link_tag / javascript_include_tag が自動付与する
    # `Link: rel=preload` レスポンスヘッダー(HTTP/2 Server Push 向け)を無効化する。
    # 本番は HTTP/2 Push を使っておらず、ブラウザには preload ヒントとしてのみ解釈されるため、
    # 「preload されたが使われていない」という警告(コンソール)の原因になっていた。
    config.action_view.preload_links_header = false
  end
end
