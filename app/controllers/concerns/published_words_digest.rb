# 公開(注釈済み)の語全体の「版」を表す軽い指紋。
# 全件を1レスポンスに書き出す重いエンドポイント(sitemap.xml / llms-full.txt)が、
# キャッシュキーと条件付きGET(ETag / Last-Modified)の両方に使う。
#
# 版を「日単位」に畳んでいるのが肝。
# 語義の保存は touch: true で words.updated_at を動かすため、素の MAX(updated_at) を
# 指紋にすると「アノテーションを1語保存するたびに全件の作り直しが必要になる」状態になる。
# 本番は Puma 1プロセス・MRI は GIL なので、その数秒の再生成が走っている間はサイト全体と
# 管理画面が止まる。クローラは遠慮なく取りに来るので、
#   保存 → クローラが取りに来る → 数秒 CPU を握られる → 次の「保存して次へ」が待たされる
# という詰まりが常時発生していた(「語の切り替えに毎回1〜3秒かかる」の主因)。
#
# 日単位に畳むと、1日じゅうアノテーションしても作り直しは最大1回で済む。
# どちらの出力も Cache-Control で1日の猶予を宣言している(expires_in 1.day, public)ので、
# 最大1日の遅れは元々の契約どおりで、公開側の鮮度を新たに損ねてはいない。
module PublishedWordsDigest
  extend ActiveSupport::Concern

  # 同じキャッシュキーで同時に再生成が始まるのを防ぐ猶予(キャッシュ・スタンピード対策)。
  # 期限切れの直後に複数リクエストが来ても、作り直すのは1本だけになる。
  RACE_CONDITION_TTL = 1.minute

  private

  # 版 = 公開語の最終更新日(その日の始まり)。その日のうちの更新はすべて同じ版に畳まれる。
  #
  # 収録語数を混ぜてはいけない。アノテーションの保存は「未公開の語を公開する」操作なので
  # 公開語数が必ず1増える。件数を版に含めると、日単位に畳んでも保存のたびに版が変わってしまい、
  # 畳んだ意味が無くなる(実測: 1万語規模で保存のたびに sitemap 1.5秒 + 全文 5.7秒の再生成)。
  #
  # 削除だけが起きた場合は最終更新日が動かないが、キャッシュ自体に1日の有効期限が
  # あるので、遅くとも翌日には作り直される。
  def published_words_version
    @published_words_version ||= Word.annotated.maximum(:updated_at)&.in_time_zone&.beginning_of_day
  end

  def published_words_digest
    published_words_version&.to_i.to_s
  end

  def published_words_last_modified
    published_words_version
  end
end
