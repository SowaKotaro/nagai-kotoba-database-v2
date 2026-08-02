# 収録リクエスト・フォームの「表示時刻」を署名して持ち回すトークン(Issue 75)。
#
# 人間はフォームを開いてから送信までに必ず数秒かかる。開いた時刻を署名付きで持たせ、
# 短すぎる送信を自動投稿とみなして捨てるための時間トラップ。署名しているので、
# クライアント側で時刻を細工しても通らない。
#
# 期限切れ(フォームを開いたまま放置した場合)は「自動投稿」ではなく人間の可能性が高いので、
# 呼び出し側では捨てずに再送を促すこと(:invalid と :too_fast を分けているのはそのため)。
module WordRequestFormToken
  PURPOSE = :word_request_form
  # 開いたまま放置されたフォームの猶予。これを過ぎたトークンは無効になる。
  EXPIRES_IN = 1.day
  # 人間の入力にはこれ以上かかる。下回る送信は自動投稿とみなす。
  # 短すぎる送信は黙って捨てるため、正当な利用者を巻き込まない値にする:
  # 検索0件からの導線は語がプリフィルされており「開いてすぐ送る」があり得るので、
  # 秒数を欲張らない(ハニーポットとの二重防御で、ここ単独の精度は追わない)。
  MIN_ELAPSED = 2.seconds

  module_function

  # フォームの hidden に埋める署名済みトークン。
  def issue
    verifier.generate(Time.current.to_i, purpose: PURPOSE, expires_in: EXPIRES_IN)
  end

  # :ok(人間らしい) / :too_fast(速すぎる = ボット) / :invalid(署名不正・期限切れ・欠落)。
  def verify(token)
    issued_at = verifier.verified(token.to_s, purpose: PURPOSE)
    return :invalid if issued_at.blank?

    Time.current.to_i - issued_at.to_i < MIN_ELAPSED ? :too_fast : :ok
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
