# 言語的特徴の「調べたうえで該当なし」を記録する(Issue 76)。
#
# 特徴が0件の語義には「まだ調べていない」と「調べたが該当する現象が無かった」の
# 2種類が混ざっている。区別できないと、再調査のたびに同じ語を突き返すことになる。
class AddFeaturesReviewedAtToWordSenses < ActiveRecord::Migration[8.1]
  def change
    add_column :word_senses, :features_reviewed_at, :datetime,
               comment: "言語的特徴を調査した日時(該当なしの確定を含む)"
    # 「特徴0件 かつ 未調査」の語義を引くための索引。書き出しの対象抽出で使う。
    add_index :word_senses, :features_reviewed_at, name: "idx_word_senses_features_reviewed_at"
  end
end
