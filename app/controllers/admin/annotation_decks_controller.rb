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

  private

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
