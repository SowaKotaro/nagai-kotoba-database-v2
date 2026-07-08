class Word < ApplicationRecord
  # 1つの表層形に対し複数の語義を持つ(同音異義語に対応)。
  has_many :word_senses, dependent: :destroy
  # Claude Code の調査結果(アノテーション提案)の下書き。語ごとに1件(Issue 38)。
  has_one :annotation_proposal, dependent: :destroy
  # 管理画面から語義をネストして登録・編集する。空行はスキップ、_destroy で削除可。
  accepts_nested_attributes_for :word_senses, allow_destroy: true, reject_if: :all_blank

  validates :surface, presence: true, uniqueness: true

  # アノテーション・コンソールの未注釈キュー(annotated_at が未セットの語)。
  scope :unannotated, -> { where(annotated_at: nil) }
  # 公開対象。注釈済み(annotated_at あり)の語だけを全世界に見せる。
  scope :annotated, -> { where.not(annotated_at: nil) }
  # 未承認の提案(Claude の下書き)が付いている語。コンソールの「提案あり」フィルタ用(Issue 38)。
  scope :with_pending_proposal, -> { joins(:annotation_proposal).merge(AnnotationProposal.pending) }

  # 簡素検索(キーワードのみ): 表層形・読みの部分一致。ワイルドカードはエスケープする。
  scope :keyword, lambda { |text|
    pattern = "%#{sanitize_sql_like(text)}%"
    joins(:word_senses)
      .where("words.surface LIKE :pattern OR word_senses.reading LIKE :pattern", pattern: pattern)
      .distinct
  }

  # 注釈完了とみなす時刻をセットする(保存は呼び出し側で行う)。
  def mark_annotated
    self.annotated_at = Time.current
  end

  # 表層形は textarea 入力(折り返し表示)のため、混入した改行を先に除去する。
  before_validation :strip_surface_newlines
  # char_type_pattern は surface から常に導出する(手入力させない)。
  before_validation :assign_char_type_pattern

  private

  def strip_surface_newlines
    # 改行は語の区切りになり得るため空白へ置換し(例: 貼り付けの折り返し)、前後の空白を除去する。
    # 内部の既存スペース(例「Dead by Daylight」)は保持する。
    self.surface = surface.gsub(/[\r\n]+/, " ").strip if surface
  end

  def assign_char_type_pattern
    self.char_type_pattern = CharTypePattern.call(surface)
  end
end
