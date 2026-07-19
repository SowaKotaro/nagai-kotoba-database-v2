# 開発環境専用のダミーデータ(db/seeds.rb から development のときだけ load される)。
# 本番はジャンルの小分類・語義が多く、統計ページ(サンバースト等)の使い勝手は
# ローカルの少量データでは再現できない。ここで本番相当以上のボリュームを投入する。
#
# 内容: SeedCatalog 投入済みの 大分類 × 先頭6中分類 の下に小分類を段階的な数
# (3〜36件)でぶら下げ、各小分類へ 1〜3 語(語義)を付けて公開状態にする。
# 冪等: 目印の語(開発語 0001)が既にあれば何もしない。
# 片付け: Word.where("surface LIKE '開発語 %'").destroy_all と
#         Genre.small.where("name LIKE '開発小分類%'").destroy_all で削除できる。

if Word.exists?([ "surface LIKE ?", "開発語 %" ])
  puts "開発用ダミーデータは投入済みのためスキップしました。"
else
  kana = %w[ア イ ウ エ オ カ キ ク ケ コ サ シ ス セ ソ タ チ ツ テ ト
            ナ ニ ヌ ネ ノ ハ ヒ フ ヘ ホ マ ミ ム メ モ ヤ ユ ヨ ラ リ ル レ ロ ワ
            ガ ギ グ ゲ ゴ ザ ジ ズ ゼ ゾ ダ デ ド バ ビ ブ ベ ボ パ ピ プ ペ ポ]
  # counter を種にした決定的な擬似乱数で読み(カタカナ)を作る。
  # サイトの趣旨(読み10文字以上の長い言葉)に合わせて基本は10〜15文字、
  # 40語に1語は30文字以上(読みの長さ分布の「30+」まとめ棒の確認用)。
  build_reading = lambda do |counter|
    random = Random.new(counter)
    length = (counter % 40).zero? ? 30 + counter % 13 : 10 + counter % 6
    Array.new(length) { kana[random.rand(kana.size)] }.join
  end

  mediums_per_large = 6
  small_counts = [ 3, 6, 10, 16, 24, 36 ]  # 中分類ごとの小分類数(少ない棒〜細分化された棒まで揃える)
  senses_per_small = [ 1, 1, 2, 3 ]        # 小分類ごとの語数

  word_counter = 0
  small_total = 0
  ActiveRecord::Base.transaction do
    Genre.large.order(:id).find_each do |large|
      large.children.order(:id).limit(mediums_per_large).each_with_index do |medium, medium_index|
        small_counts[medium_index % small_counts.size].times do |small_index|
          small = Genre.find_or_create_by!(parent: medium, level: :small,
                                           name: "開発小分類 #{medium.id}-#{small_index + 1}")
          small_total += 1
          senses_per_small[(small_total + small_index) % senses_per_small.size].times do
            word_counter += 1
            word = Word.new(surface: format("開発語 %04d", word_counter))
            word.mark_annotated
            word.word_senses.build(reading: build_reading.call(word_counter), genre: small)
            word.save!
          end
        end
      end
    end
  end
  puts "開発用ダミーデータを投入しました: 小分類 #{small_total} 件 / 語 #{word_counter} 件"
end
