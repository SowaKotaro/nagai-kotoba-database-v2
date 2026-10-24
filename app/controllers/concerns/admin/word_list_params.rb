# 単語の修正(管理一覧)の検索・絞り込み・ページ位置。一覧から入る画面(1語の修正・まとめて付ける・まとめて外す)が
# 戻り先で同じ一覧を出せるよう、受け渡すキーをここだけで持つ(Issue 108)。
module Admin::WordListParams
  extend ActiveSupport::Concern

  # 語義のタグ(マスタの id)での絞り込み。言語学的特徴は該当部分(FEATURE_TARGET_KEY)でも絞れる。
  TAG_FILTER_KEYS = %i[genre_id part_of_speech_id entity_type_id word_origin_id linguistic_feature_id].freeze
  FEATURE_TARGET_KEY = :feature_target
  KEYS = [ :q, :status, :page, *TAG_FILTER_KEYS, FEATURE_TARGET_KEY ].freeze

  included do
    # 一覧の行のリンクと、修正画面の戻り先・隠しフィールドで使う
    helper_method :word_list_params
  end

  private

  # 値は一覧の絞り込み(Admin::WordsController#tag_filters_from_params)と同じく前後の空白を落とす。
  def word_list_params
    params.permit(*KEYS).to_h.transform_values { |value| value.to_s.strip }.compact_blank
  end
end
