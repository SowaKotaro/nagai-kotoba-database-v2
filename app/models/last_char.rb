# 読み(reading)から末尾文字を取り出す値オブジェクト。
# 末尾が長音符 ー の場合、単に最後の1文字を取ると「ー」自体になってしまう
# (例: 「ハンバーガー」→「ー」)。末尾から連続する ー をすべて取り除いてから
# 最後の1文字を取ることで、直前の長音以外の文字を末尾文字とする(例: 「ガ」)。
#
# 本来は first_char と同じく SQL の STORED 生成カラムにしたいが、生成式に
# マルチバイト文字を含めると ActiveRecord の SchemaDumper(MySQL2 アダプタ)が
# schema.rb をダンプする際に文字化けする既知の制限があるため、last_char だけ
# 例外的に Ruby 側(WordSense の before_validation)で計算する。
class LastChar
  CHOUON = "ー" # 長音符

  # reading から末尾文字を返す。nil / 空文字は nil。
  def self.call(reading)
    text = reading.to_s.sub(/#{CHOUON}+\z/, "")
    text.empty? ? nil : text[-1]
  end
end
