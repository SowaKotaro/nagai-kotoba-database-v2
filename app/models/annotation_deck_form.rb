# アノテーション・デッキ(まとめてアノテーション)の「入力途中の状態」を、送られてきた
# パラメータからメモリ上に組み直す(保存はしない)。
#
# 提案の新設候補マスタをその場で作るとき(Admin::AnnotationDecksController#create_master)は、
# デッキのフォームごとサーバへ送る。デッキは1つのフォームに複数語を抱えるため、1語コンソールの
# ように「作成 → リダイレクトして再反映」にすると、他のカードの入力まで消えてしまう。
# そこで送信内容をそのまま Word へ流し込み、入力済みの内容を保ったまま描き直す。
#
# 保存は AnnotationDeckSave が担う。こちらは「描き直すためだけ」に組み立てる。
class AnnotationDeckForm
  # deck_params: { "12" => 許可済みの語パラメータ, ... }(キーは語 id・並びはカードの順)
  def initialize(deck_params)
    @deck_params = deck_params
  end

  # 送信内容を流し込んだ Word の配列。並びは送信順(= カードの並び)を保つ。
  def words
    ordered_words.map { |id, word| assign(word, @deck_params[id]) }
  end

  private

  # 送られてきた語をまとめて引く(id ごとの find で N+1 にしない)。存在しない id は無視する。
  def ordered_words
    words = Word.where(id: @deck_params.keys)
                .includes(word_senses: %i[genre word_origins word_sense_features word_sense_variants])
                .index_by { |word| word.id.to_s }
    @deck_params.keys.filter_map { |id| [ id, words[id] ] if words[id] }
  end

  def assign(word, word_params)
    attributes = word_params.deep_dup
    origin_ids = extract_origin_ids(attributes)
    word.assign_attributes(attributes)
    assign_origins(word, origin_ids)
    word.word_senses.build if word.word_senses.empty?
    word
  end

  # 語種(has_many :through)の ids 代入は、永続化済みの語義だと即 DB へ書き込まれてしまう。
  # ここは保存しない組み直しなので、ids はパラメータから外しておき(→ assign_origins で
  # association の target をメモリ上に立てる)、ProposalApplication の GET 反映と同じ扱いにする。
  # 戻り値は [語義 id(新規は nil), 語種 id の配列] の組を送信順に並べたもの。
  def extract_origin_ids(attributes)
    senses = attributes[:word_senses_attributes]
    return [] if senses.blank?

    senses.values.map do |sense|
      [ sense[:id].presence, Array(sense.delete(:word_origin_ids)).reject(&:blank?) ]
    end
  end

  # 送信された語種を語義へメモリ上で結び付ける。既存の語義は id で、新規の語義は
  # 建てられた順で突き合わせる(フォームの並びと build の順は一致する)。
  def assign_origins(word, origin_ids)
    new_senses = word.word_senses.reject(&:persisted?)

    origin_ids.each do |sense_id, ids|
      sense = sense_id ? word.word_senses.detect { |s| s.id.to_s == sense_id } : new_senses.shift
      next unless sense

      sense.association(:word_origins).target = ids.filter_map { |id| origins_by_id[id.to_i] }
    end
  end

  # 語種マスタは数件しかないので、まとめて引いて使い回す。
  def origins_by_id
    @origins_by_id ||= WordOrigin.all.index_by(&:id)
  end
end
