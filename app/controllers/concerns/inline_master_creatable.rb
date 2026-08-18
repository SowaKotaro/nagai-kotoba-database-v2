# アノテーション・コンソールの「その場追加」(ジャンル・語種・品詞・エンティティ)で
# 共通に使う作成処理。
#
# 画面遷移せずに JSON で作るため、失敗しても利用者に見えるのは「何も起きない」だけになる。
# 一番多い失敗が「同じ名前が既にある」であることを踏まえ、
#   - 表記まで同じものが既にあれば、作らずにそれを返して選ばせる(二重登録にしない)
#   - 表記が違うのに衝突する場合(照合順序 utf8mb4_0900_ai_ci は「ハ」と「バ」、
#     ひらがな/カタカナ、大文字/小文字を同一視する)は、理由が分かるメッセージを返す
# という形にして、UI 側が必ず何かを表示できるようにしている。
module InlineMasterCreatable
  extend ActiveSupport::Concern

  private

  # scope: 重複判定と作成の対象になる関連(例: Genre.where(parent_id: 1))
  # attributes: name 以外に設定する属性(例: { level: :small })
  def create_inline_master(scope, attributes = {})
    name = inline_master_name
    return render_inline_master_error(t("admin.inline_add.blank_name")) if name.blank?

    existing = scope.find_by(name: name)
    if existing
      return render json: inline_master_json(existing).merge(existing: true) if existing.name == name

      return render_inline_master_error(t("admin.inline_add.conflict", existing: existing.name, name: name))
    end

    record = scope.new(attributes.merge(name: name))
    return render json: inline_master_json(record) if record.save

    render_inline_master_error(record.errors.full_messages)
  rescue ActiveRecord::RecordNotUnique
    # 二重送信や同時操作で検証をすり抜けた場合。エラーにせず既存を返して選ばせる。
    duplicated = scope.find_by(name: name)
    return render_inline_master_error(t("admin.inline_add.retry")) if duplicated.nil?

    render json: inline_master_json(duplicated).merge(existing: true)
  end

  # 前後の空白(全角スペースを含む)を落とす。空白だけの名前は空扱いにする。
  def inline_master_name
    params[:name].to_s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
  end

  def inline_master_json(record)
    { id: record.id, name: record.name }
  end

  def render_inline_master_error(messages)
    render json: { errors: Array(messages) }, status: :unprocessable_entity
  end
end
