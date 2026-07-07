# Claude Code の調査結果(アノテーション提案)。word と 1:1 の下書き(Issue 38)。
# payload(JSON)は取り込み時の形をそのまま保持し、マスタ名 → id の解決は表示・反映時に
# その都度行う(取り込み後にマスタを追加しても、再取り込みせずに解決できるように)。
# annotated_at を立てる(公開する)のは人間のコンソール保存だけで、提案自体は公開面に影響しない。
class AnnotationProposal < ApplicationRecord
  belongs_to :word

  # pending: 未承認 / applied: コンソールで保存済み / dismissed: 見送り
  enum :status, { pending: 0, applied: 1, dismissed: 2 }, default: :pending

  validates :payload, presence: true

  # --- payload の読み出し(キーは文字列で保持) ---
  def meaning = payload["meaning"].presence

  # ジャンルは名前のパス(大→中→小)で受け取る。
  def genre_path = Array(payload["genre_path"]).map(&:to_s).reject(&:blank?)

  def entity_type_name = payload["entity_type"].presence
  def part_of_speech_name = payload["part_of_speech"].presence
  def word_origin_names = Array(payload["word_origins"]).map(&:to_s).reject(&:blank?)

  # 別表記の提案(surface 必須・reading 任意)。
  def variants
    Array(payload["variants"]).select { |v| v.is_a?(Hash) && v["surface"].present? }
  end

  def confidence = payload["confidence"].presence
  def notes = payload["notes"].presence

  # 立項スコア(1〜5)。docs/annotation-guidelines.md の収録4原則への適合度。範囲外・未評価は nil。
  def entry_score
    value = payload["entry_score"].to_i
    value if value.between?(1, 5)
  end

  # 立項の懸念理由(どの原則を・なぜ欠くか)。スコア3以下の語に付く。
  def entry_notes = payload["entry_notes"].presence

  # 3以下は「オーナー判断が必要」ゾーン。コンソールの提案パネルで朱バッジを出す。
  def entry_concern?
    entry_score.present? && entry_score <= 3
  end

  # --- マスタ名の解決(見つからなければ nil = 新設候補) ---

  # ジャンルパスを既存の木から辿り、末端の小分類まで解決できたときだけ Genre を返す。
  # 途中までしか無い・小分類でない場合は nil(コンソールのその場追加で作ってから反映する)。
  def resolved_genre
    genre = genre_path.inject(nil) do |parent, name|
      found = Genre.find_by(name: name, parent_id: parent&.id)
      break nil unless found

      found
    end
    genre if genre&.small?
  end

  def resolved_entity_type = EntityType.find_by(name: entity_type_name)
  def resolved_part_of_speech = PartOfSpeech.find_by(name: part_of_speech_name)

  # 見つかった語種だけを返す(見つからない名前は unknown_word_origin_names)。
  def resolved_word_origins
    WordOrigin.where(name: word_origin_names)
  end

  def unknown_word_origin_names
    word_origin_names - resolved_word_origins.pluck(:name)
  end
end
