# 単語(表層形+読み)をテキストエリアからまとめて登録するフォームオブジェクト。
# 1行 = 1件。「表層形␣読み」形式(区切りは半角空白/全角空白/タブ)。
# 読みは単一トークン(かな)なので、行の最後の空白区切りで表層形と読みに分ける。
#   → 表層形に半角空白を含む語(例: "Dead by Daylight")も正しく扱える。
# 登録はジャンル等を付けず未注釈のまま行い、後段のアノテーションで整える。
# 冪等: 既存の(表層形,読み)はスキップする。行ごとに独立処理し、結果を集計して返す。
class BulkWordRegistration
  include ActiveModel::Model

  attr_accessor :text

  # 表層形と読みの区切り: 行末側の空白(半角/タブ/全角空白)のかたまり。
  SEPARATOR = /[[:blank:]　]+/

  # 登録結果の集計。created=新規登録, skipped=既存, errors=登録できなかった行の説明。
  Result = Struct.new(:created, :skipped, :errors, keyword_init: true)

  validates :text, presence: true

  # 解析して登録する。行ごとに独立して処理し、結果(Result)を返す。
  def register
    created = 0
    skipped = 0
    errors = []

    parsed_lines.each do |line_no, surface, reading|
      if surface.blank? || reading.blank?
        errors << error_line(line_no, I18n.t("admin.words.bulk.errors.missing_field"))
        next
      end

      outcome = register_one(surface, reading)
      case outcome
      when :created then created += 1
      when :skipped then skipped += 1
      else errors << error_line(line_no, outcome)
      end
    end

    Result.new(created: created, skipped: skipped, errors: errors)
  end

  private

  # 1件を登録する。:created / :skipped、失敗時はエラーメッセージ文字列を返す。
  # 表層形の作成と読みの追加は1件単位でトランザクションにまとめる。
  def register_one(surface, reading)
    ActiveRecord::Base.transaction do
      word = Word.find_or_create_by!(surface: surface)
      sense = word.word_senses.find_or_initialize_by(reading: reading)
      next :skipped if sense.persisted?

      sense.save!
      :created
    end
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.full_messages.join("、")
  end

  # 各行を [行番号, 表層形, 読み] に分解する(空行は飛ばす)。
  def parsed_lines
    text.to_s.each_line.with_index(1).filter_map do |raw, line_no|
      line = raw.strip
      next if line.blank?

      before, separator, after = line.rpartition(SEPARATOR)
      # 区切りが無い行は読み欠落(表層形のみ)として扱う。
      surface, reading = separator.empty? ? [ line, nil ] : [ before.strip, after.strip ]
      [ line_no, surface, reading ]
    end
  end

  def error_line(line_no, detail)
    I18n.t("admin.words.bulk.error_line", line: line_no, detail: detail)
  end
end
