# Claude Code の調査結果(アノテーション提案)。word ごとに1件の下書き(Issue 38)。
# payload(JSON)は取り込み時の形をそのまま保持し、マスタ名 → id の解決は表示・反映時に
# その都度行う(取り込み後にマスタを追加しても、再取り込みせずに解決できるように)。
# annotated_at を立てる(公開する)のは人間のコンソール保存だけで、提案自体は公開面に影響しない。
#
# 語義は複数持てる(Issue 41: 同一表記の同音異義語)。payload["senses"] が配列ならそれを
# 語義ごとの提案とみなし、無ければ従来のトップレベル形式(単一語義)を1件として扱う。
# confidence / notes / entry_score / entry_notes は語全体のメタで語義に依らない。
class AnnotationProposal < ApplicationRecord
  belongs_to :word

  # pending: 未承認 / applied: コンソールで保存済み / dismissed: 見送り
  enum :status, { pending: 0, applied: 1, dismissed: 2 }, default: :pending

  # 立項スコアの範囲(docs/annotation-guidelines.md §2 の 5 段階)。表記の確認(WordCandidate)の entry_score も同じ範囲。
  # Ruby だけが当てる範囲で、SQL の needs_review は範囲外の値も「要判断」に入れる(下のスコープを参照)。
  ENTRY_SCORE_RANGE = 1..5
  # 立項スコアがこれ以下の語は「オーナー判断が必要」(docs/annotation-guidelines.md §2)。
  # コンソールの赤いバッジ・キューの「要判断」・一括承認のゲートが、この 1 つの境界を共有する。
  ENTRY_CONCERN_MAX_SCORE = 3
  # 確信度(docs/annotation-guidelines.md §8)のうち、判定に使う両端の値。
  # 語彙は WordCandidate::CONFIDENCES と同じ(どちらも Claude の調査スキルの出力)。
  HIGH_CONFIDENCE = "high"
  LOW_CONFIDENCE = "low"

  # コンソールのキューで「要判断」に絞る(Issue 67)。立項スコアが低い(ENTRY_CONCERN_MAX_SCORE 以下)か確信度が low の提案。
  # payload(JSON)から取り出す。joins された words クエリからも呼べるよう列を明示修飾する。
  # 範囲外の立項スコア(0・負の値・数値でない文字列)は、CAST で 0 以下になるので「要判断」に入る。
  # Ruby の entry_score は同じ値を nil(未評価)として扱うので、範囲外の値では両者の判定が食い違う。
  scope :needs_review, -> {
    where("CAST(annotation_proposals.payload->>'$.entry_score' AS SIGNED) <= ? " \
          "OR annotation_proposals.payload->>'$.confidence' = ?", ENTRY_CONCERN_MAX_SCORE, LOW_CONFIDENCE)
  }

  validates :payload, presence: true

  # 語義ごとの提案(意味・ジャンル・エンティティ・品詞・語種・別表記・読み)を持つ値オブジェクト。
  # マスタ名 → レコードの解決もここで行う(見つからなければ nil = 新設候補)。
  class SenseProposal
    def initialize(data)
      @data = data.is_a?(Hash) ? data : {}
    end

    def meaning = @data["meaning"].presence
    # 語義ごとに読みが変わる場合のみ(通常は語の読みを共有するので省略される)。
    def reading = @data["reading"].presence

    # ジャンルは名前のパス(大→中→小)で受け取る。
    def genre_path = Array(@data["genre_path"]).map(&:to_s).reject(&:blank?)

    def entity_type_name = @data["entity_type"].presence
    def part_of_speech_name = @data["part_of_speech"].presence
    def word_origin_names = Array(@data["word_origins"]).map(&:to_s).reject(&:blank?)

    # 別表記の提案(surface 必須・reading 任意)。
    def variants
      Array(@data["variants"]).select { |v| v.is_a?(Hash) && v["surface"].present? }
    end

    # 言語的特徴の提案。name/target/target_reading が揃った要素だけを返す。
    # target_reading も必須にするのは WordSenseFeature が両方を必須にするためで、
    # 欠けたものは反映しても保存できない(パネルには出さず、反映もしない)。
    # 除外したことはどこにも表示しないので、一括承認では不完全な特徴が落ちたまま公開される(variants も同じ)。
    def linguistic_features
      Array(@data["linguistic_features"]).select do |f|
        f.is_a?(Hash) && f["name"].present? && f["target"].present? && f["target_reading"].present?
      end
    end

    # ジャンルパス(大→中→小)を既存の木から辿れるところまでの Genre 鎖を返す。
    # 末端まで一致すれば [大, 中, 小]、途中までなら [大] や [大, 中]、1つも無ければ []。
    # 名前の解決は name 列の照合順序(ai_ci)に任せる。清濁・かなの種類・全角半角だけが違う名前は、
    # 既存の同じマスタに解決される(docs/data-model.md §6)。末尾の空白は区別される。
    def resolved_genre_chain
      chain = []
      parent = nil
      genre_path.each do |name|
        found = Genre.find_by(name: name, parent_id: parent&.id)
        break unless found

        chain << found
        parent = found
      end
      chain
    end

    # 末端の小分類まで解決できたときだけ Genre を返す(genre_id に入れてよい確定値)。
    # 途中までしか無い場合は nil(大・中は resolved_genre_chain でピッカーを開くのに使う)。
    def resolved_genre
      last = resolved_genre_chain.last
      last if last&.small?
    end

    def resolved_entity_type = EntityType.find_by(name: entity_type_name)
    def resolved_part_of_speech = PartOfSpeech.find_by(name: part_of_speech_name)

    # 見つかった語種だけを返す(見つからない名前は unknown_word_origin_names)。
    def resolved_word_origins = WordOrigin.where(name: word_origin_names)
    def unknown_word_origin_names = word_origin_names - resolved_word_origins.pluck(:name)

    # 特徴名を既存マスタに解決する(無ければ nil = 新設候補)。
    def resolved_linguistic_feature(feature) = LinguisticFeature.find_by(name: feature["name"])
  end

  # 語義ごとの提案。payload["senses"] があればそれを、無ければトップレベル形式を1件とみなす。
  def senses
    raw = payload["senses"]
    hashes = raw.is_a?(Array) && raw.any? ? raw.select { |h| h.is_a?(Hash) } : [ legacy_sense_hash ]
    hashes.map { |hash| SenseProposal.new(hash) }
  end

  # 複数語義(同音異義語)の提案か(パネルの見出し出し分け・語義複製の判断に使う)。
  def multiple_senses? = senses.size > 1

  # --- 語全体のメタ(語義に依らない) ---
  def confidence = payload["confidence"].presence
  def notes = payload["notes"].presence

  # 立項スコア(ENTRY_SCORE_RANGE)。docs/annotation-guidelines.md の収録4原則への適合度。範囲外・未評価は nil。
  # (SQL の needs_review は範囲外の値を「要判断」に入れる。上のスコープを参照)
  def entry_score
    value = payload["entry_score"].to_i
    value if ENTRY_SCORE_RANGE.cover?(value)
  end

  # 立項の懸念理由(どの原則を・なぜ欠くか)。スコア3以下の語に付く。
  def entry_notes = payload["entry_notes"].presence

  # ENTRY_CONCERN_MAX_SCORE 以下は「オーナー判断が必要」ゾーン。コンソールの提案パネルで赤いバッジを出す。
  def entry_concern?
    entry_score.present? && entry_score <= ENTRY_CONCERN_MAX_SCORE
  end

  # --- 後方互換: 単一語義時代の呼び出し口は先頭語義に委譲する ---
  delegate :meaning, :reading, :genre_path, :resolved_genre, :entity_type_name,
           :resolved_entity_type, :part_of_speech_name, :resolved_part_of_speech,
           :word_origin_names, :resolved_word_origins, :unknown_word_origin_names, :variants,
           to: :first_sense

  private

  def first_sense = senses.first || SenseProposal.new({})

  # トップレベル形式(単一語義)を語義ハッシュに切り出す。
  def legacy_sense_hash
    payload.slice("meaning", "reading", "genre_path", "genre_new", "entity_type",
                  "part_of_speech", "word_origins", "variants")
  end
end
