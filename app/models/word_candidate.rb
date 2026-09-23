# 登録予定単語(登録前の前処理)。
#
# 調査スキル(/expand・/notation)の実行はローカルの Claude Code のまま、
# 「どの語がどの段階まで進んだか」をこのテーブルのステータスで追う。流れは次の4段:
#
#   upload → expand → duplicate → notation → done(一括登録へ貼る) → 登録済み
#
# - upload: 貼り付けた直後。一覧で「expand に回す語」と「そのまま duplicate に回す語」を選ぶ
#   (同じ系統の語を2つ expand すると調査が重なるため、系統ごとに1語だけ expand に回す)。
# - expand / notation: ステータスは「その段にいる」ことを表し、結果を取り込んだかは
#   expanded_at / notated_at で分かる(取り込み済みの語を画面の最後にまとめて次の段へ送る)。
# - 本流から外した語は 要判断(pending)・重複(duplicated)・不要(rejected) に置く。
#   不要にした語も消さずに残し、表層形のユニーク制約で「一度見た語」の集合を兼ねる
#   (同じ語が expand / harvest から再流入したとき、取り込み時に弾けるようにするため)。
class WordCandidate < ApplicationRecord
  MAX_SURFACE_LENGTH = 255
  MAX_NOTE_LENGTH = 1000
  CONFIDENCES = %w[high medium low].freeze
  # notation の立項スコアがこれ以下の語は「立項に疑義がある語」として要判断へ回す
  # (word-notation-research が上部リストから外す基準と同じ)。
  DOUBTFUL_ENTRY_SCORE = 2

  # 値は流れの順に並べ、間を空けておく(段を差し込めるように)。
  enum :status, {
    upload: 10, expand: 20, duplicate: 30, notation: 40, done: 50, registered: 60,
    pending: 80, duplicated: 85, rejected: 90
  }, validate: true

  # 前処理の4段(横並びの流れ図と、各段の画面)。
  FLOW_STEPS = %w[upload expand duplicate notation].freeze

  # 一覧で選べる処理 => 移す先のステータス。expand・duplicate はその段の画面へ移る。
  ACTIONS = {
    "to_expand" => "expand", "to_duplicate" => "duplicate", "to_pending" => "pending",
    "to_rejected" => "rejected", "to_upload" => "upload"
  }.freeze

  # まだ手が離れていない語(4段のどこかにいるか、要判断)。
  scope :in_progress, -> { where(status: %i[upload expand duplicate notation pending]) }
  # 元の語の直後に、expand で増えた語が並ぶ順(upload した順を保つ)。
  scope :in_tree_order, -> { order(Arel.sql("COALESCE(word_candidates.root_id, word_candidates.id), word_candidates.id")) }

  belongs_to :seed, class_name: "WordCandidate", optional: true
  belongs_to :root, class_name: "WordCandidate", optional: true
  belongs_to :word, optional: true
  has_many :expansions, class_name: "WordCandidate", foreign_key: :seed_id, inverse_of: :seed, dependent: :nullify

  validates :surface, presence: true, length: { maximum: MAX_SURFACE_LENGTH }, uniqueness: true
  validates :note, length: { maximum: MAX_NOTE_LENGTH }
  validates :entry_score, numericality: { only_integer: true, in: 1..5 }, allow_nil: true
  validates :confidence, inclusion: { in: CONFIDENCES }, allow_nil: true

  before_validation :normalize_surface
  before_save :stamp_status_changed_at, if: :will_save_change_to_status?

  # 一括登録で語が収録されたら、同じ表層形の登録予定単語を「登録済み」にして語と結び付ける。
  # 一括登録の step2・3 は表層形を編集させない(hidden で持ち回す)ため、表層形の一致で取りこぼさない。
  def self.register_for!(word)
    where(surface: word.surface).where.not(status: :registered).find_each do |candidate|
      candidate.update!(status: :registered, word: word)
    end
  end

  # メモに追記する(調査の注記を取り込むたびに消さずに積む)。上限を超える分は切り詰める。
  def self.append_note(note, addition)
    [ note.presence, addition.to_s.strip.presence ].compact.join(" / ").truncate(MAX_NOTE_LENGTH).presence
  end

  # 一覧で選んだ処理を当てる。段に入り直す語は「取り込み済み」を消し、書き出し直せるようにする。
  def self.apply_action!(candidates, action)
    status = ACTIONS.fetch(action)
    attributes = { status: status, notated_at: nil }
    attributes[:expanded_at] = nil if status.in?(%w[expand upload])
    transaction do
      candidates.each { |candidate| candidate.update!(attributes) }
    end
  end

  # この語から expand で増やす語に持たせる属性(元の語と、系統の根)。
  def expansion_attributes
    { seed: self, root_id: root_id || id }
  end

  private

  # 表層形は textarea 貼り付けで改行が混ざりうる。内部の既存スペース(例「Dead by Daylight」)は
  # 語の一部なので保持する(Word#strip_surface_newlines と同じ扱い)。
  # upload した時点の表記は、notation で置き換わっても辿れるよう original_surface に残す。
  def normalize_surface
    self.surface = surface.gsub(/[\r\n]+/, " ").strip if surface
    self.original_surface ||= surface
  end

  def stamp_status_changed_at
    self.status_changed_at = Time.current
  end
end
