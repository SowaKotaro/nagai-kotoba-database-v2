# SNS の自動投稿(本番の cron から毎時に動かす。docs/sns-autopost-setup.md)。規則は SnsBroadcast・SnsRotation・SnsPostText が持つ。
namespace :sns do
  desc "SNS の自動投稿: いまの正時の枠の語を決め(sns_slots の slot_at・word_id・round を書く)、認証情報のある SNS へ送って、" \
       "結果を sns_posts(platform・status・remote_id・error_message・posted_at)に残す。同じ時刻に何度動かしても、" \
       "SNS ごとに 1 回しか投稿しない(失敗した SNS だけ送り直す)。どれかの SNS が失敗したら終了コード 1 で終わる。" \
       "DRY_RUN=1 で、投稿も DB への書き込みもせずに、次に出す文面を表示する。" \
       "WORD_ID=1 で、いまの枠がまだ無ければ、選ばずにその語を出す(最初の投稿など。公開語で本文が収まる語に限る)"
  task post: :environment do
    if ENV["DRY_RUN"].present?
      slot = SnsSlot.find_by(slot_at: Time.current.beginning_of_hour)
      word_id = slot&.word_id || ENV["WORD_ID"].presence
      word = word_id ? Word.includes(:word_senses).find_by(id: word_id) : SnsRotation.new.call&.word
      abort "出せる語がありません" unless word

      message = SnsPostText.message(word)
      puts message.body, "", "返信(Bluesky・Threads): #{message.link.url}"
      puts "", "送り先: #{SnsBroadcast.configured_clients.keys.join(", ").presence || "(認証情報がありません)"}"
      next
    end

    result = SnsBroadcast.new(word_id: ENV["WORD_ID"].presence).call
    abort "送り先がないか、出せる語がありません" unless result.slot

    puts "#{result.slot.slot_at.iso8601} #{result.slot.word.surface}"
    errors = result.slot.sns_posts.to_h { [ it.platform.to_sym, it.error_message ] }
    result.outcomes.each { |platform, outcome| puts "  #{platform}: #{outcome} #{errors[platform]}".rstrip }
    exit 1 if result.failed?
  end
end
