# 特徴の該当部分に「出現位置(表層形の先頭からの文字オフセット)」を持たせる。
# 同じ表層形の同じ語に同じ特徴を複数回付けられるようにするための拡張。
#   例:「…びしょびしょの実家でびしょびしょの父親と…」に オノマトペ:びしょびしょ を3箇所付ける。
# これまでの一意制約 (word_sense_id, linguistic_feature_id, target) では、同一 target が
# 1回しか登録できず、繰り返し出現する語に同じ特徴を複数付与できなかった。
# target_start を一意キーに含め、出現箇所ごとに別レコードとして登録できるようにする。
class AddTargetStartToWordSenseFeatures < ActiveRecord::Migration[8.1]
  def up
    # 先頭からの文字オフセット(0始まり)。既存行は後段で最初の出現位置に埋める。
    unless column_exists?(:word_sense_features, :target_start)
      add_column :word_sense_features, :target_start, :integer,
                 comment: "該当部分の出現位置(表層形の先頭からの文字オフセット・0始まり)"
    end

    # 既存行のバックフィル: target が surface のどこに現れるかの最初の位置。
    # マルチバイトの文字数で数える(SQL の LOCATE はバイトではなく文字位置を返すので INSTR を使う)。
    backfill_target_start

    # NOT NULL だが DB 既定値は置かない。新規行はモデルの before_validation が出現位置を
    # 必ず埋める(既定値0にすると .new が0で埋まり出現位置の補完が働かないため)。
    change_column_null :word_sense_features, :target_start, false

    # 一意制約を target_start 込みに張り替える(出現箇所ごとに別レコードを許可)。
    # 旧一意インデックスは word_sense_id への外部キーが依存するため、先に新インデックス
    # (これも word_sense_id が先頭)を張ってから旧インデックスを落とす。
    unless index_exists?(:word_sense_features, %i[word_sense_id linguistic_feature_id target target_start],
                         name: "uq_wsf_sense_feature_target_start")
      add_index :word_sense_features,
                %i[word_sense_id linguistic_feature_id target target_start],
                name: "uq_wsf_sense_feature_target_start",
                unique: true,
                length: { target: 191 }
    end
    if index_exists?(:word_sense_features, nil, name: "uq_wsf_sense_feature_target")
      remove_index :word_sense_features, name: "uq_wsf_sense_feature_target"
    end
  end

  def down
    # 外部キーが依存するため、旧一意インデックスを先に張ってから新インデックスを落とす。
    unless index_exists?(:word_sense_features, %i[word_sense_id linguistic_feature_id target],
                         name: "uq_wsf_sense_feature_target")
      add_index :word_sense_features,
                %i[word_sense_id linguistic_feature_id target],
                name: "uq_wsf_sense_feature_target",
                unique: true,
                length: { target: 191 }
    end
    if index_exists?(:word_sense_features, nil, name: "uq_wsf_sense_feature_target_start")
      remove_index :word_sense_features, name: "uq_wsf_sense_feature_target_start"
    end
    remove_column :word_sense_features, :target_start
  end

  private

  # INSTR は1始まり・見つからなければ0を返す。0始まりに合わせて 1 を引き、
  # 見つからない場合(理論上は無い)は 0 にフォールバックする。
  def backfill_target_start
    execute(<<~SQL.squish)
      UPDATE word_sense_features wsf
      JOIN word_senses ws ON ws.id = wsf.word_sense_id
      JOIN words w ON w.id = ws.word_id
      SET wsf.target_start = GREATEST(INSTR(w.surface, wsf.target) - 1, 0)
    SQL
  end
end
