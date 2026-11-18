# SNS の自動投稿の 1 回ぶん(rake sns:post が毎時に呼ぶ)。いまの正時の枠(SnsSlot)の語を決め、
# 設定のある SNS へ順に送って、結果を SNS ごとに sns_posts へ残す。
#
# - 同じ時刻に何度呼んでも、SNS ごとに 1 回しか投稿しない。送る前に「送信中」の行を作り、(枠, SNS) の一意制約で取り合う。
#   失敗した SNS だけは、同じ時刻のうちに呼び直せば送り直す。過ぎた枠には戻らない(遅れた投稿を後から出さない)。
# - 1 つの SNS が落ちても、ほかの SNS には送る(クライアントは例外を投げずに Result を返す)。
# - 外部へ送るのはクライアント(app/services の BlueskyClient・XClient)。クライアントは publish(message) で SnsClient::Result を返す。
# 種別: 書き込み処理。
class SnsBroadcast
  # outcomes は { platform => :posted / :failed / :skipped }。slot は語が無くて送らなかったとき nil。
  Result = Data.define(:slot, :outcomes) do
    def failed? = outcomes.value?(:failed)
  end

  # 設定(認証情報)のある SNS のクライアント。{ platform => client }。
  def self.configured_clients
    { bluesky: BlueskyClient.from_config, x: XClient.from_config }.compact
  end

  # word_id を渡すと、いまの枠がまだ無いときに限り、選ばずにその語で枠を作る(最初の投稿や特別な日の語を決めて出す。
  # rake sns:post の WORD_ID)。公開語で、本文が収まる語に限る。巡は今の巡のまま(その巡では、もう選ばれない)。
  def initialize(clients: self.class.configured_clients, now: Time.current, random: Random.new, word_id: nil)
    @clients = clients
    @now = now
    @random = random
    @word_id = word_id
  end

  def call
    return Result.new(slot: nil, outcomes: {}) if @clients.empty?

    slot = current_slot
    # 語が消えたか、非公開に戻した(注釈の保留)枠は送らない。
    return Result.new(slot: nil, outcomes: {}) unless slot && Word.annotated.exists?(slot.word_id)

    message = build_message(slot.word_id)
    Result.new(slot:, outcomes: @clients.to_h { |platform, client| [ platform, deliver(slot, platform, client, message) ] })
  end

  # いまの正時の枠。まだ無ければ語を選んで作る。出せる語が無ければ nil。
  def current_slot
    slot_at = @now.beginning_of_hour
    SnsSlot.find_by(slot_at:) || create_slot(slot_at)
  end

  private

  def create_slot(slot_at)
    pick = @word_id ? chosen_pick : SnsRotation.new(random: @random).call
    return unless pick

    SnsSlot.create!(slot_at:, word: pick.word, round: pick.round)
  rescue ActiveRecord::RecordNotUnique
    SnsSlot.find_by!(slot_at:) # 同じ時刻の別の実行が先に作った
  end

  def chosen_pick
    word = Word.annotated.includes(:word_senses).find(@word_id)
    raise ArgumentError, "本文が X の上限に収まらない語です(#{word.surface})" unless SnsPostText.fits?(word)

    SnsRotation::Pick.new(word:, round: SnsSlot.maximum(:round) || 1)
  end

  def build_message(word_id)
    word = Word.includes(:word_senses).find(word_id)
    SnsPostText.message(word, image: share_card_png(word))
  end

  # リンクのカードの画像(Bluesky)。焼けない環境では nil で、画像の無いカードになる。
  def share_card_png(word)
    card = WordShareCard.new(word)
    return unless card.renderable? && ShareCardRenderer.available?

    ShareCardRenderer.new.fetch(name: "word-#{word.id}", version: card.digest, svg: card.svg)
  end

  def deliver(slot, platform, client, message)
    post = claim(slot, platform)
    return :skipped unless post

    result = client.publish(message)
    error_message = result.error&.truncate(SnsPost::MAX_ERROR_LENGTH)
    if result.success?
      post.update!(status: :posted, remote_id: result.remote_id, posted_at: Time.current, error_message:)
      :posted
    else
      post.update!(status: :failed, error_message:)
      :failed
    end
  end

  # この枠・この SNS へ送る権利を取る。取れなければ nil(投稿済み・送信中・別の実行が取った)。
  def claim(slot, platform)
    slot.sns_posts.create!(platform:, status: :sending)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    post = slot.sns_posts.find_by(platform:)
    return unless post&.failed?

    # 失敗した行を送り直す。2 つの実行が同時に取りに来ても 1 つだけが取れるよう、条件つきの UPDATE で取る
    # (update_all はコールバックを通らないが、この表に派生値は無い)。
    claimed = SnsPost.where(id: post.id, status: :failed).update_all(status: SnsPost.statuses[:sending], updated_at: Time.current)
    claimed == 1 ? post.reload : nil
  end
end
