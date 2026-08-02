# 公開側から届いた収録リクエスト1通(Issue 75)。
#
# 1通に最大 MAX_ITEMS 語まで入り、送信の技術メタデータ(IP・User-Agent・リファラー・
# 送信元パス)は語行ではなく「通」側にだけ持つ。レートリミットはこの通数を数えるので、
# 「1語を10回送信」と「10語を1回送信」を取り違えずに判定できる。
#
# 保存するメタデータの範囲と利用目的(不正投稿の防止・導線改善の分析)は
# プライバシーポリシー(pages#privacy)で公表している。
class WordRequest < ApplicationRecord
  # 1通あたりの語数上限。クライアントの行数制御だけに頼らず、ここでも検証する。
  MAX_ITEMS = 10

  # レートリミット [期間, その期間に許す通数]。保存済みレコードの COUNT で判定するため、
  # 送信については自前のカウンタを持たない(確定事項 #20)。
  RATE_LIMITS = [ [ 1.hour, 5 ], [ 1.day, 20 ] ].freeze

  has_many :items, class_name: "WordRequestItem", dependent: :destroy, inverse_of: :word_request
  # 空行(表層形も読みもひとことも空)は行ごと捨てる。10行出しておいて1行だけ書く使い方に備える。
  accepts_nested_attributes_for :items, reject_if: :all_blank

  validates :ip_address, presence: true
  validates :items, presence: true
  validate :items_within_limit

  # 直近の送信数が上限に達している IP か(いずれかの期間で超えていれば true)。
  def self.rate_limited?(ip_address)
    return false if ip_address.blank?

    RATE_LIMITS.any? do |period, limit|
      where(ip_address: ip_address, created_at: period.ago..).count >= limit
    end
  end

  private

  def items_within_limit
    errors.add(:base, :too_many_items, count: MAX_ITEMS) if items.size > MAX_ITEMS
  end
end
