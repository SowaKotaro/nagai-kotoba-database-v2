# 高速アノテーション・コンソール。1語を大きく表示し、語義・語種・ジャンル・品詞・
# エンティティ・言語学的特徴・別表記を素早く付与して「保存して次へ」で流す。
# キューは未対応(annotation_status: pending)の語を id 順に辿る。保留(on_hold)にした語は
# キューから外れ、あとで単語一覧の「保留」フィルタから見直せる。
# ?proposed=1 を付けると、Claude の提案(pending)が付いた語だけを辿る(Issue 38)。
class Admin::AnnotationsController < Admin::BaseController
  before_action :set_word, only: %i[show update hold create_master]

  # キューの最初の語へ誘導。無ければ完了画面(index ビュー)を出す。
  def index
    first = queue_scope.order(:id).first
    redirect_to admin_annotation_path(first, proposed: proposed_param) if first
  end

  def show
    @word.word_senses.build if @word.word_senses.empty?
    # 提案は status を問わず表示する(注釈済みの語を「戻る」で見直すときも Claude の提案を
    # 参照できるように)。反映(apply)は明示操作か、提案キューでの自動反映のときだけ行う。
    @proposal = AnnotationProposal.find_by(word_id: @word.id)
    if apply_proposal?
      apply_proposal_defaults
    else
      apply_sticky_defaults
    end
    load_masters
    set_navigation
  end

  def update
    @word.assign_attributes(annotation_params)
    @word.mark_annotated
    remember_sticky_toggle
    if @word.save
      remember_sticky_values
      mark_proposal_applied
      redirect_to_next_word(t("admin.annotations.saved"))
    else
      @proposal = AnnotationProposal.find_by(word_id: @word.id)
      load_masters
      set_navigation
      render :show, status: :unprocessable_entity
    end
  end

  # 現在の語を保留にしてキューから外し、次の未対応へ進む。フォームの入力内容は保存しない
  # (まだ確定できないから保留する運用のため、途中入力の妥当性を問わない)。
  def hold
    @word.mark_on_hold
    @word.save!
    redirect_to_next_word(t("admin.annotations.held"))
  end

  # 提案の「新設候補」マスタをワンタップ作成し、提案を再反映して戻る(Issue 66)。
  # 作成後は解決してフォームに自動で入る。新設候補は基本 単一語義なので先頭語義を対象にする。
  def create_master
    proposal = AnnotationProposal.find_by(word_id: @word.id)
    raise ActiveRecord::RecordNotFound unless proposal

    ProposedMasterCreation.new(proposal.senses.first, params[:field], params[:name]).create!
    redirect_to admin_annotation_path(@word, apply_proposal: 1, proposed: proposed_param)
  rescue ProposedMasterCreation::Error, ActiveRecord::RecordInvalid
    redirect_to admin_annotation_path(@word, apply_proposal: 1, proposed: proposed_param),
                alert: t("admin.annotations.create_master_failed")
  end

  private

  # 保存/保留のあと、キューに残る次の語(無ければ完了画面)へ誘導する。
  # ?proposed=1 のフィルタは保ったまま辿る。
  def redirect_to_next_word(notice)
    next_word = queue_scope.where.not(id: @word.id).order(:id).first
    redirect_to(next_word ? admin_annotation_path(next_word, proposed: proposed_param)
                          : admin_annotations_path(proposed: proposed_param),
                notice: notice)
  end

  def set_word
    @word = Word.includes(word_senses: %i[word_origins word_sense_features word_sense_variants])
                .find(params[:id])
  end

  # チップ選択で使うマスタ一式。
  def load_masters
    @word_origins = WordOrigin.order(:name)
    @parts_of_speech = PartOfSpeech.order(:name)
    @entity_types = EntityType.order(:name)
    @linguistic_features = LinguisticFeature.order(:name)
    @large_genres = Genre.large.order(:name)
  end

  # --- Claude の提案(Issue 38) ---

  # 提案をフォームへ反映するか。明示操作(apply_proposal=1)に加え、提案キュー(?proposed=1)では
  # 未承認提案を開いた時点で自動反映する(毎語「提案を反映」を押す手間と GET 往復を省く・Issue 64)。
  # 自動反映は pending の提案だけ(反映済み/見送りは二重反映しない)。提案があればスティッキー
  # 引き継ぎより優先する。
  def apply_proposal?
    return false unless @proposal
    return true if params[:apply_proposal] == "1"

    proposed_param.present? && @proposal.pending?
  end

  # 「提案を反映」: 提案の値をフォームの初期値として流し込む(保存はしない。人間が確認・修正
  # して保存した時点で承認)。組み立ては ProposalApplication に集約し、一括承認(Issue 65)と
  # 同じ規則で反映する。
  def apply_proposal_defaults
    ProposalApplication.new(@word, @proposal).build
  end

  # 保存(承認)された語の提案は applied にする。
  def mark_proposal_applied
    AnnotationProposal.pending.find_by(word_id: @word.id)&.applied!
  end

  # 「提案あり」フィルタ(?proposed=1)を保ったままキューを辿るための値。
  def proposed_param
    params[:proposed].presence
  end

  # コンソールのキュー。既定は未対応(pending)の語、?proposed=1 なら未承認の提案が付いた語だけ。
  # 保留(on_hold)にした語はキューに出ない。
  def queue_scope
    scope = Word.annotation_pending
    scope = scope.with_pending_proposal if proposed_param
    scope
  end

  # --- スティッキー引き継ぎ(Issue 37) ---
  # 同質な語が並ぶキューで、直前に保存した語のジャンル・エンティティ・品詞・語種を
  # 次の語の初期値にする。トグル(画面のチェックボックス)の状態と直前の値はセッションに持つ。

  # 属性が何も付いていない語義にだけ、直前の値を初期値として流し込む。
  # GET で呼ぶため保存はしない。語種は ids 代入だと永続化済みの語義で即時に
  # DB へ書かれてしまうので、読み込み済みの関連 target をメモリ上で差し替える。
  def apply_sticky_defaults
    return unless session[:annotation_sticky]

    values = session[:annotation_sticky_values]
    return if values.blank?

    sticky_origins = WordOrigin.where(id: values["word_origin_ids"]).to_a

    @word.word_senses.each do |sense|
      next if sense.genre_id || sense.entity_type_id || sense.part_of_speech_id || sense.word_origins.any?

      sense.genre_id = values["genre_id"]
      sense.entity_type_id = values["entity_type_id"]
      sense.part_of_speech_id = values["part_of_speech_id"]
      sense.association(:word_origins).target = sticky_origins.dup
    end
  end

  # トグルの ON/OFF は保存の成否に関わらず記憶する(OFF にしたら直前の値も忘れる)。
  def remember_sticky_toggle
    session[:annotation_sticky] = params[:sticky] == "1"
    session.delete(:annotation_sticky_values) unless session[:annotation_sticky]
  end

  # 保存に成功した語の先頭語義から、引き継ぐ値を覚える。
  def remember_sticky_values
    return unless session[:annotation_sticky]

    sense = @word.word_senses.reject(&:marked_for_destruction?).first
    return unless sense

    session[:annotation_sticky_values] = {
      "genre_id" => sense.genre_id,
      "entity_type_id" => sense.entity_type_id,
      "part_of_speech_id" => sense.part_of_speech_id,
      "word_origin_ids" => sense.word_origin_ids
    }
  end

  # キューの残数と、スキップ(次の語)・戻る(直前の語)のリンク先。?proposed=1 も同じキューを辿る。
  def set_navigation
    # queue_scope は ?proposed=1 で annotation_proposals を joins するため、
    # 素の id は words.id / annotation_proposals.id で曖昧になる。words.id に明示修飾する。
    words_id = Word.arel_table[:id]
    @remaining = queue_scope.count
    @skip_word = queue_scope.where(words_id.gt(@word.id)).order(words_id).first ||
                 queue_scope.where.not(id: @word.id).order(words_id).first
    @prev_word = Word.where(words_id.lt(@word.id)).order(words_id.desc).first
  end

  # 語種は多対多(word_origin_ids)、ジャンル/品詞/エンティティは belongs_to の *_id、
  # 特徴・別表記はネスト属性。表層形(surface)の訂正もここで受ける(Issue 36: 編集画面を
  # コンソールへ統合。char_type_pattern は before_validation で再生成される)。
  def annotation_params
    params.require(:word).permit(
      :surface,
      word_senses_attributes: [
        :id, :_destroy, :reading, :meaning, :genre_id, :entity_type_id, :part_of_speech_id,
        { word_origin_ids: [],
          word_sense_features_attributes: %i[id _destroy linguistic_feature_id target target_reading target_start],
          word_sense_variants_attributes: %i[id _destroy surface reading] }
      ]
    )
  end
end
