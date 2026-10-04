ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # フィクスチャの読み込みはコールバックを通らないため、words のランキング指標
    # (語義の代表値。WordSenseMetrics)が埋まらない。読み込み後に一度そろえておく。
    # テストの中で作った語は after_commit(RefreshesWordMetrics)が追従するので、
    # ここで必要なのはフィクスチャぶんだけ。テストのトランザクション内なので巻き戻る。
    setup { WordSenseMetrics.refresh! }

    # かなの畳み込みの特性テストの入力。畳み込みは呼び出し元ごとに範囲・NFKC の有無が違うので、
    # 同じ入力に対するいまの出力をそれぞれのテストで固定している。
    # 中身: 半角カナ「ｶﾞｷﾞ」(4 字)・合成濁点つきの「か」(2 字)・ゔ・ゕ・ゖ。
    KANA_FOLD_SAMPLE = [ 0xFF76, 0xFF9E, 0xFF77, 0xFF9E, 0x304B, 0x3099, 0x3094, 0x3095, 0x3096 ].pack("U*").freeze

    # テストが前提にする本番ホスト(config.x.canonical_host の既定値)。設定から読まずにリテラルで書くのは、
    # 「既定値がこの URL であること」も固定するため(環境変数 CANONICAL_HOST を設定した環境では落ちる)。
    CANONICAL_HOST = "https://nagai-kotoba-database.jp".freeze

    # 公開語を 1 語つくる(語義 1 つ)。公開は mark_annotated で立てる(annotated_at と状態「完了」の両方)。
    # Word.create!(annotated_at: ...) だけだと、本番には無い「公開済みなのに未対応」の語になり、
    # アノテーションのキュー(annotation_pending)に混ざる。
    def create_published_word(surface:, reading:, **sense_attributes)
      word = Word.new(surface: surface)
      word.word_senses.build(reading: reading, **sense_attributes)
      word.mark_annotated
      word.save!
      word
    end

    # Rails.cache(モデルの集計キャッシュ)をブロックの間だけメモリのストアにする。test 環境は :null_store で、
    # 差し替えないとキャッシュを一度も通らない。
    def with_rails_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end

    # ビューの cache ブロック(フラグメントキャッシュ)を、ブロックの間だけ効かせる。
    # 書き込み先は Rails.cache ではなく、起動時に取り込んだ ActionController::Base.cache_store なので、
    # こちらを差し替える(Rails.cache だけを差し替えたテストは一度もキャッシュを通っていなかった)。
    def with_fragment_cache
      original_perform_caching = ActionController::Base.perform_caching
      original_store = ActionController::Base.cache_store
      ActionController::Base.perform_caching = true
      ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      ActionController::Base.perform_caching = original_perform_caching
      ActionController::Base.cache_store = original_store
    end

    # Rails.application.config.x の値を、ブロックの間だけ差し替えて元の値に戻す。
    #   with_config(indexing_enabled: false) { ... }
    def with_config(**settings)
      config = Rails.application.config.x
      original = settings.keys.index_with { |key| config.public_send(key) }
      settings.each { |key, value| config.public_send("#{key}=", value) }
      yield
    ensure
      original&.each { |key, value| config.public_send("#{key}=", value) }
    end

    # 環境変数を、ブロックの間だけ差し替えて元に戻す(元に無かったものは消す)。
    #   with_env("PATH" => "") { ... }
    def with_env(vars)
      original = vars.keys.index_with { |key| ENV.fetch(key, :absent) }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      original&.each { |key, value| value == :absent ? ENV.delete(key) : ENV[key] = value }
    end

    # クラス/シングルトンメソッドをブロックの間だけ差し替える。
    # minitest 6 は Object#stub を持たないため、テスト用に自前で用意する。
    def stub_method(object, method_name, replacement)
      original = object.method(method_name)
      object.singleton_class.define_method(method_name) { |*args, **kwargs| replacement.call(*args, **kwargs) }
      yield
    ensure
      object.singleton_class.define_method(method_name, original)
    end
  end
end
