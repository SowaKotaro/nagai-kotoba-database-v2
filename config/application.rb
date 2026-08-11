require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module NagaiKotobaDatabaseV2
  class Application < Rails::Application
    # フレームワークの既定値(Issue 55 で 7.1 から引き上げ)。
    # 7.1 のままだと 7.2/8.0/8.1 の新既定が一切効かないため、Rails 8.1 の運用に揃えた。
    # 本アプリに実際の影響があるのは次の4つ。いずれも導入時に動作を確認済み。
    #   - action_dispatch.strict_freshness (8.0): 条件付き GET で ETag を
    #     Last-Modified より優先する(RFC 7232 準拠)。sitemap.xml・llms-full.txt は
    #     両方を送っているため挙動が変わるが、304 が返ることを確認済み。
    #   - Regexp.timeout = 1 (8.0): Ruby 側の正規表現に1秒の上限。公開検索の
    #     正規表現は MySQL 側で評価する(SearchRegexp)ので影響はなく、ReDoS への保険になる。
    #   - action_view.render_tracker = :ruby (8.1): フラグメントキャッシュの
    #     依存検出を正規表現から Ruby パーサへ。/search のジャンルフィルタが
    #     _genre_chip の変更を拾えることを確認済み。
    #   - yjit (8.1): 本番のみ有効。Rails 側が defined?(RubyVM::YJIT.enable) で
    #     ガードしているため、YJIT 無しでビルドされた Ruby でも起動する。
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # 日本語話者向けのサイトなので、表示と「今日 / 今月」の判定を日本時間で行う。
    # 未設定(既定の UTC)のままだと、日本時間の 0:00〜9:00 に収録した語の日付が
    # 前日として表示され、「今月の新収録」の集計も月初・月末で1日ずれる。
    # DB への保存は Rails 既定どおり UTC のままなので、既存データの変換は不要。
    config.time_zone = "Tokyo"
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

    # 収録リクエストの受付スイッチ(Issue 75)。荒らされたら本番の環境変数を "false" にして
    # 即座に閉じられるようにする。未設定は受付ON(インデックス解禁と違い既定で有効)。
    config.x.requests_enabled =
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("REQUESTS_ENABLED", "true")) || false

    # stylesheet_link_tag / javascript_include_tag が自動付与する
    # `Link: rel=preload` レスポンスヘッダー(HTTP/2 Server Push 向け)を無効化する。
    # 本番は HTTP/2 Push を使っておらず、ブラウザには preload ヒントとしてのみ解釈されるため、
    # 「preload されたが使われていない」という警告(コンソール)の原因になっていた。
    config.action_view.preload_links_header = false
  end
end
