# 高速アノテーション・コンソール。1語を大きく表示し、語義・語種・ジャンル・品詞・
# エンティティ・言語学的特徴・別表記を素早く付与して「保存して次へ」で流す。
# キューは未対応(annotation_status: pending)の語を id 順に辿る。保留(on_hold)にした語は
# キューから外れ、あとで単語一覧の「保留」フィルタから見直せる。
# ?proposed=1 を付けると、Claude の提案(pending)が付いた語だけを辿る(Issue 38)。
class Admin::AnnotationsController < Admin::BaseController
  # キュー(絞り込み・並べ替え)とマスタ読み込みは 10件デッキと共有する。
  include Admin::AnnotationQueue

  before_action :set_word, only: %i[show update hold create_master reresearch review_features]

  # キューの最初の語へ誘導。無ければ完了画面(index ビュー)を出す。
  def index
    # 入口は提案付きの語を優先する(Issue 69)。
    return redirect_to admin_annotations_path(proposed: 1) if enter_proposed_queue?

    first = ordered_queue.first
    return redirect_to admin_annotation_path(first, nav_params) if first

    # 完了画面。提案キュー(?proposed=1)を捌き切っても提案なしの未対応語が残っていることが
    # あるため、残数を数えて書き出し(下調べの補充)への導線を出し分ける(Issue 69)。
    @pending_count = Word.annotation_pending.count
    @proposed_count = Word.annotation_pending.with_pending_proposal.count
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

  # 言語的特徴を「調べたが該当する現象は無かった」で確定する(Issue 76)。
  #
  # 特徴が0件の語義には「まだ調べていない」と「調べたうえで該当なし」が混ざる。
  # 後者を記録しておかないと、特徴の再調査を掛けるたびに同じ語が対象に戻ってくる。
  # 特徴が既に付いている語義は対象にしない(付いている時点で調査済みのため)。
  def review_features
    targets = @word.word_senses.reject { |sense| sense.word_sense_features.any? }
    WordSense.where(id: targets.map(&:id)).update_all(features_reviewed_at: Time.current)
    redirect_to admin_annotation_path(@word, nav_params),
                notice: t("admin.annotations.features_reviewed")
  end

  # 提案の「新設候補」マスタをワンタップ作成し、提案を再反映して戻る(Issue 66)。
  # 作成後は解決してフォームに自動で入る。新設候補は基本 単一語義なので先頭語義を対象にする。
  def create_master
    proposal = AnnotationProposal.find_by(word_id: @word.id)
    raise ActiveRecord::RecordNotFound unless proposal

    ProposedMasterCreation.new(proposal.senses.first, params[:field], params[:name]).create!
    redirect_to admin_annotation_path(@word, nav_params.merge(apply_proposal: 1))
  rescue ProposedMasterCreation::Error, ActiveRecord::RecordInvalid
    redirect_to admin_annotation_path(@word, nav_params.merge(apply_proposal: 1)),
                alert: t("admin.annotations.create_master_failed")
  end

  # 1語の再調査用 JSON(現在の注釈内容 + マスタ一覧)をコピーする画面。
  # ここでコピーした JSON を Claude Code の /reannotation に貼ると、項目を選んで
  # 調べ直した提案 JSON が返り、それを「提案 JSON の取り込み」に貼って上書きする。
  # マスタ込みで数十 KB になるためコンソール本体には埋め込まず、この画面に分ける。
  def reresearch
    @proposal = AnnotationProposal.find_by(word_id: @word.id)
    @reresearch_json = ReannotationExport.new(@word, @proposal).to_json
  end

  private

  # 保存/保留のあと、キューに残る次の語(無ければ完了画面)へ誘導する。
  # 提案フィルタ・並べ替え・要判断フィルタ(nav_params)は保ったまま辿る。
  def redirect_to_next_word(notice)
    next_word = ordered_queue.where.not(id: @word.id).first
    redirect_to(next_word ? admin_annotation_path(next_word, nav_params)
                          : admin_annotations_path(nav_params),
                notice: notice)
  end

  def set_word
    @word = Word.includes(word_senses: %i[word_origins word_sense_features word_sense_variants])
                .find(params[:id])
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

  # キューの残数と、スキップ(順序上の次)・戻る(順序上の前)のリンク先。並べ替え(Issue 67)に
  # 追従させるため、キューの語 id を順序どおりに取り出して現在語の前後を採る。
  # (提案キューは取り込み単位で高々数百件なので、id 列の取得は軽い。words.id は
  # annotation_proposals.id との曖昧を避けるため明示修飾する。)
  def set_navigation
    ordered_ids = ordered_queue.pluck("words.id")
    @remaining = ordered_ids.size
    position = ordered_ids.index(@word.id)
    @skip_word = skip_target(ordered_ids, position)
    @prev_word = prev_target(ordered_ids, position)
  end

  # スキップ先(順序上の次)。末尾なら先頭へ回り込み、現在語がキュー外なら先頭。
  def skip_target(ordered_ids, position)
    return Word.find_by(id: ordered_ids.first) if position.nil?

    next_id = ordered_ids[position + 1] || ordered_ids.find { |id| id != @word.id }
    Word.find_by(id: next_id)
  end

  # 戻る先(順序上の前)。無ければ id が小さい直近の語(既存挙動のフォールバック)。
  def prev_target(ordered_ids, position)
    prev_id = ordered_ids[position - 1] if position&.positive?
    (Word.find_by(id: prev_id) if prev_id) ||
      Word.where(Word.arel_table[:id].lt(@word.id)).order(id: :desc).first
  end

  # 許可属性の集合はデッキと共有する(Admin::AnnotationQueue::WORD_ATTRIBUTES)。
  def annotation_params
    params.require(:word).permit(*WORD_ATTRIBUTES)
  end
end
