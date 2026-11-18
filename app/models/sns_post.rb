# 枠(SnsSlot)ごと・SNS ごとの投稿の記録。送る前に「送信中」で行を作り、
# (枠, SNS) の一意制約で、cron が重なっても同じ SNS へ 2 度送らないようにする(SnsBroadcast)。
class SnsPost < ApplicationRecord
  MAX_ERROR_LENGTH = 1000

  belongs_to :sns_slot

  # 値は間を空けておく(SNS を足せるように)。X の名前は 1 文字なので、述語とスコープには接頭辞を付ける。
  enum :platform, { bluesky: 10, x: 20, threads: 30 }, prefix: true, validate: true
  # 送信中のまま残った行(送っている途中でプロセスが落ちた)は、投稿できたかどうかが分からないので送り直さない。
  enum :status, { sending: 10, posted: 20, failed: 90 }, validate: true

  validates :platform, uniqueness: { scope: :sns_slot_id }
  validates :error_message, length: { maximum: MAX_ERROR_LENGTH }
end
