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
