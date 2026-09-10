# アノテーション・デッキ(まとめてアノテーション)。キューの先頭から既定10件をまとめて読み込み、
# 横に並べたカードを行き来しながら注釈を付け、最後に1回の送信でまとめて保存・公開する。
#
# 1語ずつのコンソール(Admin::AnnotationsController)は「保存 → 次の語を取りに行く」ため、
# 1語ごとにサーバ往復と画面遷移が挟まる。同質な語をまとめて捌くときはその待ちが効くので、
# 読み込みと保存をそれぞれ1回にまとめたのがこの画面。キューの規則(絞り込み・並べ替え)は
# Admin::AnnotationQueue で1語コンソールと共有し、2画面で出てくる語が食い違わないようにする。
#
# 提案(Claude の下書き)は開いた時点で全カードに反映済みにする(1語コンソールの提案キューと
# 同じ既定)。人間はカードを送りながら直すだけでよい。
class Admin::AnnotationDecksController < Admin::BaseController
  include Admin::AnnotationQueue

  # 1デッキの枚数。多すぎると1画面の DOM(マスタのチップ×枚数)が重くなり、少なすぎると
  # まとめる意味が薄れる。既定10枚・上限20枚。
  DEFAULT_SIZE = 10
  MAX_SIZE = 20

  def show
    # 入口は1語コンソールと同じく提案付きの語を優先する(Issue 69)。
    return redirect_to admin_annotation_deck_path(proposed: 1) if enter_proposed_queue?

    load_deck
    load_masters
  end

  # デッキのまとめ保存。語ごとに独立して保存し、通った語だけ公開する。
  # 全件通れば次のデッキへ、落ちた語があればその語だけデッキに残してエラーを見せる
  # (1件の不備で残り9件の入力までやり直しにしないため)。
  def update
    result = AnnotationDeckSave.new(deck_params).call
    if result.failed.empty?
      return redirect_to admin_annotation_deck_path(nav_params.merge(size_param)),
                         notice: t(".saved", count: result.saved.size)
    end

    @words = result.failed
    @proposals = proposals_for(@words)
    @remaining = queue_scope.count
    load_masters
    flash.now[:alert] = t(".partially_saved", saved: result.saved.size, failed: result.failed.size)
    render :show, status: :unprocessable_entity
  end

  # 提案の「新設候補」マスタをその場で作る(1語コンソールの create_master のデッキ版・Issue 66)。
  #
  # 1語コンソールは button_to で単独のフォームを置けるが、デッキは1つのフォームに複数語を
  # 抱えているのでフォームを入れ子にできない。そこでデッキのフォームごとこのアクションへ送り、
  # 作成したマスタを対象の語義に入れたうえで、送信内容から画面を組み直して返す
  # (リダイレクトすると他のカードの入力まで消えるため、Turbo Stream で差し替える)。
  def create_master
    word = Word.find(params[:word_id])
    master = create_proposed_master(word)

    @words = AnnotationDeckForm.new(deck_params).words
    apply_created_master(@words.find { |candidate| candidate.id == word.id }, master)
    @proposals = proposals_for(@words)
    @remaining = queue_scope.count
    load_masters

    render turbo_stream: [
      turbo_stream.replace("annotation-deck", partial: "admin/annotation_decks/deck"),
      turbo_stream.update("flash", partial: "shared/flash")
    ]
  end

  private

  # 提案の新設候補マスタを1つ作る。作れなければ理由を出して nil を返す(入力はそのまま残す)。
  # 対象の語義は提案の並び(sense_index)で指す。
  def create_proposed_master(word)
    proposal = AnnotationProposal.find_by(word_id: word.id)
    sense_proposal = proposal&.senses&.[](sense_index)
    raise ProposedMasterCreation::Error, "no proposal for word #{word.id}" unless sense_proposal

    master = ProposedMasterCreation.new(sense_proposal, params[:field], params[:name]).create!
    flash.now[:notice] = t(".created", name: master.name)
    master
  rescue ProposedMasterCreation::Error, ActiveRecord::RecordInvalid
    flash.now[:alert] = t("admin.annotations.create_master_failed")
    nil
  end

  # 作ったマスタを対象の語義へ入れる(1語コンソールの「作成 → 提案を再反映」に当たる)。
  # 提案の語義とカードの語義は並びで対応する(ProposalApplication が先頭から順に使うため)。
  def apply_created_master(word, master)
    return unless word && master

    sense = word.word_senses.reject(&:marked_for_destruction?)[sense_index]
    return unless sense

    case master
    when Genre        then sense.genre = master
    when EntityType   then sense.entity_type = master
    when PartOfSpeech then sense.part_of_speech = master
    when WordOrigin   then add_origin(sense, master)
    end
  end

  # 語種は多対多。永続化済みの語義に ids で入れると即 DB へ書かれるので、
  # 保存前のこの段階では association の target をメモリ上で足すだけにする。
  def add_origin(sense, origin)
    association = sense.association(:word_origins)
    association.target = (association.target + [ origin ]).uniq
  end

  def sense_index
    params[:sense_index].to_i
  end

  # デッキに載せる語を読み込み、提案があればフォームの初期値として反映しておく。
  def load_deck
    @words = ordered_queue
               .includes(word_senses: %i[genre word_origins word_sense_features word_sense_variants])
               .limit(deck_size)
               .to_a
    @proposals = proposals_for(@words)
    @remaining = queue_scope.count

    @words.each do |word|
      word.word_senses.build if word.word_senses.empty?
      proposal = @proposals[word.id]
      # 未承認の提案だけ自動反映する(反映済み/見送りは二重に流し込まない)。
      ProposalApplication.new(word, proposal).build if proposal&.pending?
    end
  end

  def proposals_for(words)
    AnnotationProposal.where(word_id: words.map(&:id)).index_by(&:word_id)
  end

  # 語 id をキーにした { "12" => 許可済みパラメータ } の組。フォームは
  # deck[<word_id>][...] で送るため、語ごとに permit する。
  def deck_params
    deck = params.require(:deck)
    deck.keys.index_with { |word_id| deck.require(word_id).permit(*WORD_ATTRIBUTES) }
  end

  # 1デッキの枚数(?size=5 など)。指定なし・数値でない・範囲外は既定に丸める。
  def deck_size
    size = params[:size].to_i
    return DEFAULT_SIZE unless size.positive?

    [ size, MAX_SIZE ].min
  end

  # 保存後のリダイレクトで枚数指定を保つ(既定なら付けない)。
  def size_param
    params[:size].present? ? { size: deck_size } : {}
  end
end
