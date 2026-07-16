# 詳細検索の正規表現入力(MySQL の REGEXP に渡すパターン)を扱う値オブジェクト。
#
# MySQL の REGEXP は照合順序(utf8mb4_0900_as_ci)のかな同一視が効かず、
# 「あ」と「ア」を別の文字として扱う(英字の大文字小文字だけは畳まれる)。
# 読みはカタカナで格納されているため、読みに当てるパターンはカタカナへ畳んでから渡す。
# 表層形は書かれたまま(漢字かな交じり)なので、こちらは入力をそのまま当てる。
class SearchRegexp
  # 長すぎるパターンは照合コストが読めないので入口で断る。
  MAX_LENGTH = 200

  HIRAGANA = "ぁ-ゖ"
  KATAKANA = "ァ-ヶ"

  def initialize(source)
    @source = source.to_s.strip
  end

  attr_reader :source

  def present? = @source.present?

  # 読み(word_senses.reading。カタカナ)に当てるパターン。
  # ひらがなで書かれた部分だけカタカナへ畳む(メタ文字は ASCII なので影響を受けない)。
  def for_reading = @source.tr(HIRAGANA, KATAKANA)

  # 表層形(words.surface)に当てるパターン。入力をそのまま使う。
  def for_surface = @source

  # 検索を実行する前に分かるエラー(:too_long / :syntax)。問題なければ nil。
  # 照合の打ち切り(regexp_time_limit 超過)は実行してみないと分からないので、ここでは検出できない。
  def error
    return @error if defined?(@error)

    @error = detect_error
  end

  private

  def detect_error
    return nil if @source.blank?
    return :too_long if @source.length > MAX_LENGTH

    :syntax unless valid_syntax?
  end

  # 構文チェックは MySQL 自身に空文字を照合させて行う。
  # REGEXP は ICU の方言で Ruby の Regexp とは受け付ける構文がずれるため、
  # Regexp.new での事前検証だと通るはずの式を弾いたり、その逆が起きたりする。
  def valid_syntax?
    ApplicationRecord.connection.select_value(
      ApplicationRecord.sanitize_sql_array([ "SELECT '' REGEXP ?", for_reading ])
    )
    true
  rescue ActiveRecord::StatementInvalid
    false
  end
end
