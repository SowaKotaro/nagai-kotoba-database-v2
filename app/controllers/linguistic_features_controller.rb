# 言語学的特徴(連濁・熟字訓・ゴママヨ など)から探すページ。誰でも閲覧できる。
# 特徴の名前だけでは何のことか伝わりにくいので、用語解説(config/linguistic_features_glossary.yml)の定義と例を
# 見てから、その特徴を持つ言葉の一覧へ進めるようにする(詳細検索ではチップの名前だけが並び、解説は畳んだヘルプの奥にある)。
class LinguisticFeaturesController < ApplicationController
  allow_unauthenticated_access only: :index

  # 1 つの特徴に添える例の数。探すためのページなので、説明は定義の 1 文に絞り、例も頭から数件だけ見せる
  # (用語解説の全文は詳細検索の畳んだヘルプにある)。用語解説の例は 3〜5 件(LinguisticFeatureGlossaryTest)。
  EXAMPLE_LIMIT = 3

  def index
    # 集計は公開語義の全件走査なので、索引と同じ PublishedSenseCounts のキャッシュを引く。
    @counts = PublishedSenseCounts.by_linguistic_feature
    # 公開語義のある特徴だけを、用語解説の順(似た特徴が隣り合う)に並べる。0 件のものは出さない(/genres と同じ)。
    @linguistic_features = LinguisticFeature.where(id: @counts.keys).in_glossary_order
  end
end
