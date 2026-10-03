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
