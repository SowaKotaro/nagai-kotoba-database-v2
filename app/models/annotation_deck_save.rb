# アノテーション・デッキ(まとめてアノテーション)の保存。語ごとに独立して保存し、
# 検証を通った語だけを注釈済み(公開)にする。
#
# 「1件でも落ちたら全部保存しない」にすると、10件のうち9件は正しく入力できていても
# 全部やり直しになる。逆に落ちた語を黙って捨てると入力が消える。そこで
# 「通った語は保存し、落ちた語はエラー付きのまま返してデッキに残す」を採る。
# 1語の中(word + word_senses + 特徴・別表記)は accepts_nested_attributes_for の保存が
# 1トランザクションにまとまるので、語義だけ保存されて語が落ちる、という中途半端は起きない。
class AnnotationDeckSave
  # saved / failed はどちらも Word の配列(failed は errors を抱えたまま返す)。
  Result = Struct.new(:saved, :failed, keyword_init: true)

  # deck_params: { "12" => 許可済みの語パラメータ, ... }(キーは語 id)
  def initialize(deck_params)
    @deck_params = deck_params
  end

  def call
    saved = []
    failed = []

    ordered_words.each do |id, word|
      word.assign_attributes(@deck_params[id])
      word.mark_annotated
      if word.save
        # 保存(承認)された語の提案は applied にする(1語コンソールと同じ扱い)。
        AnnotationProposal.pending.find_by(word_id: word.id)&.applied!
        saved << word
      else
        failed << word
      end
    end

    Result.new(saved: saved, failed: failed)
  end

  private

  # 送られてきた語を [id, Word] の組でまとめて引く(id ごとの find で N+1 にしない)。
  # 存在しない id は無視する。並びは送信順(= デッキの並び)を保ち、保存に落ちた語が
  # カードの順番どおりに戻るようにする。
  def ordered_words
    words = Word.where(id: @deck_params.keys)
                .includes(word_senses: %i[word_origins word_sense_features word_sense_variants])
                .index_by { |word| word.id.to_s }
    @deck_params.keys.filter_map { |id| [ id, words[id] ] if words[id] }
  end
end
