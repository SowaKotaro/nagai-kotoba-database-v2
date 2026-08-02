# 収録リクエスト1語分(Issue 75)。管理画面ではこの単位でステータスを動かす。
#
# 収録基準(読み WordSense::MIN_READING_LENGTH 文字以上)を満たさない語でも保存する。
# 入口で弾くと、読みの書き間違いで正当な語まで落ちるため、選別は管理側で行う。
class WordRequestItem < ApplicationRecord
  MAX_SURFACE_LENGTH = 100
  MAX_READING_LENGTH = 100
  # 管理者が却下理由などを書き残す欄(公開側からは入力しない)。
  MAX_ADMIN_MEMO_LENGTH = 300

  belongs_to :word_request

  # 未着手(既定) → 採用済み / 保留 / 却下。遷移は管理画面での手動操作。
  enum :status, { pending: 0, accepted: 1, on_hold: 2, rejected: 3 }

  validates :surface, presence: true, length: { maximum: MAX_SURFACE_LENGTH }
  validates :reading, length: { maximum: MAX_READING_LENGTH }
  validates :admin_memo, length: { maximum: MAX_ADMIN_MEMO_LENGTH }

  before_validation :normalize
  before_save :stamp_handled_at, if: :will_save_change_to_status?

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  private

  def normalize
    # 表層形は textarea 貼り付けで改行が混ざりうる。内部の既存スペース(例「Dead by Daylight」)は
    # 語の一部なので保持する(Word#strip_surface_newlines と同じ扱い)。
    self.surface = surface.gsub(/[\r\n]+/, " ").strip if surface
    self.reading = reading.gsub(/[\r\n]+/, " ").strip if reading
  end

  # 未着手から動かした時刻を残す(未着手へ戻したら消す)。
  def stamp_handled_at
    self.handled_at = pending? ? nil : Time.current
  end
end
