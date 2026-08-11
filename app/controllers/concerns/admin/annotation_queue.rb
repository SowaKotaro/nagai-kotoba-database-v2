# アノテーションのキュー(未対応の語をどの順で辿るか)と、チップ選択に使うマスタ一式。
# 1語ずつのコンソール(Admin::AnnotationsController)と 10件デッキ
# (Admin::AnnotationDecksController)で同じ規則を共有するために切り出した。
# 片方だけ絞り込み・並べ替えの規則が変わると、同じ「提案キュー」を名乗る2画面で
# 出てくる語が食い違うため、ここを唯一の定義とする。
module Admin::AnnotationQueue
  extend ActiveSupport::Concern

  # 語1件分の許可属性(Strong Parameters)。語種は多対多(word_origin_ids)、ジャンル/品詞/
  # エンティティは belongs_to の *_id、特徴・別表記はネスト属性。表層形(surface)の訂正も
  # ここで受ける(Issue 36: 編集画面をコンソールへ統合。char_type_pattern は
  # before_validation で再生成される)。1語コンソールとデッキで同じ集合を許可する。
  WORD_ATTRIBUTES = [
    :surface,
    { word_senses_attributes: [
      :id, :_destroy, :reading, :meaning, :genre_id, :entity_type_id, :part_of_speech_id,
      { word_origin_ids: [],
        word_sense_features_attributes: %i[id _destroy linguistic_feature_id target target_reading target_start],
        word_sense_variants_attributes: %i[id _destroy surface reading] }
    ] }
  ].freeze

  included do
    # ビューのリンク/フォームで、提案フィルタ(proposed)・並べ替え(sort)・要判断フィルタ(review)を
    # 保ったままキューを辿るためのパラメータ一式(Issue 38/67)。
    helper_method :nav_params
  end

  private

  # コンソールのキュー(順序なし)。既定は未対応(pending)の語、?proposed=1 なら未承認の提案が
  # 付いた語だけ。さらに ?review=1 で「要判断」の提案(立項スコア低・確信度 low)に絞る(Issue 67)。
  # 保留(on_hold)にした語はキューに出ない。
  def queue_scope
    scope = Word.annotation_pending
    if proposed_param
      scope = scope.with_pending_proposal
      scope = scope.merge(AnnotationProposal.needs_review) if params[:review] == "1"
    end
    scope
  end

  # キューに並び順を付けたもの。既定は id 順。?proposed=1 のときだけ提案メタ(確信度・立項
  # スコア)で並べ替えられる(Issue 67)。
  def ordered_queue
    queue_scope.order(queue_order)
  end

  # 並び順。sort=easy は確実な提案(確信度 高→低・立項 高→低)を先に、sort=review は要判断
  # (立項 低→高・確信度 low 先)を先に。提案メタは JSON カラムから取り出す。既定と proposed 以外は id 順。
  # 並べ替えの SQL 断片は定数(ユーザー入力を埋め込まない)。
  def queue_order
    return Word.arel_table[:id] unless proposed_param

    case params[:sort]
    when "easy"
      Arel.sql("FIELD(annotation_proposals.payload->>'$.confidence','high','medium','low'), " \
               "CAST(annotation_proposals.payload->>'$.entry_score' AS SIGNED) DESC, words.id")
    when "review"
      Arel.sql("CAST(annotation_proposals.payload->>'$.entry_score' AS SIGNED) ASC, " \
               "FIELD(annotation_proposals.payload->>'$.confidence','low','medium','high'), words.id")
    else
      Word.arel_table[:id]
    end
  end

  # 「提案あり」フィルタ(?proposed=1)を保ったままキューを辿るための値。
  def proposed_param
    params[:proposed].presence
  end

  # 入口(?proposed 無し)を提案キューへ寄せるか(Issue 69)。Claude の下調べ(提案)が残っているのに
  # 提案なしの語(surface+reading だけの手調査になる)へ着地させない。?proposed の明示指定は尊重。
  def enter_proposed_queue?
    proposed_param.blank? && Word.annotation_pending.with_pending_proposal.exists?
  end

  # リンク/フォームで提案フィルタ・並べ替え・要判断フィルタを保つためのパラメータ。
  def nav_params
    { proposed: proposed_param, sort: params[:sort].presence, review: params[:review].presence }.compact
  end

  # チップ選択で使うマスタ一式。
  def load_masters
    @word_origins = WordOrigin.order(:name)
    @parts_of_speech = PartOfSpeech.order(:name)
    @entity_types = EntityType.order(:name)
    @linguistic_features = LinguisticFeature.order(:name)
    @large_genres = Genre.large.order(:name)
  end
end
