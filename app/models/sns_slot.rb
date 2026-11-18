# SNS の自動投稿(毎時)の枠。1 時間に 1 行で、その時刻に 3 つの SNS へ出す語を持つ。
# 語は SnsRotation が選び、投稿は SnsBroadcast が SNS ごとに sns_posts へ残す。
# 語を消すと word_id は NULL になる(外部キーの on_delete: :nullify)。その枠は、もう送らない。
class SnsSlot < ApplicationRecord
  belongs_to :word, optional: true
  has_many :sns_posts, dependent: :destroy

  validates :slot_at, presence: true, uniqueness: true
  validates :round, numericality: { only_integer: true, greater_than: 0 }
end
