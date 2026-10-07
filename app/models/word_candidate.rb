# 登録予定単語(登録前の前処理)。
#
# 調査スキル(/expand・/notation)の実行はローカルの Claude Code のまま、
# 「どの語がどこで何を待っているか」をこのテーブルのステータスで追う。流れは次の4段:
#
#   仕分け → 拡張(/expand) → 表記(/notation) → 登録待ち(一括登録へ) → 登録済み
#
# ステータスは段の名前ではなく「次に何を待っているか」で表す(名前だけで次の一手が分かるように)。
# - 仕分け待ち(triage): 誰もまだ判断していない語。upload した語・/expand で集まった語・分割でできた語が入る。
#   語ごとに 拡張 / 採用 / 保留 / 除外 を選んで一度に確定する(WordCandidateDecisions)。
#   upload したままの語は、ほとんどを拡張に回すので最初から「拡張」を選んでおく。
#   重複の照合は画面に並べるたびに行い、一致した語は最初から「除外」を選んでおく(独立した段は持たない)。
# - 拡張待ち(expanding) / 表記待ち(notating): ローカルのスキルに渡して結果を待っている語。
# - 表記の確認待ち(notated): /notation の結果を取り込んだ語。表記と立項スコアを見て 採用 / 保留 / 除外 を選ぶ。
# - 登録待ち(ready): 一括登録に渡す語。登録されると登録済み(registered)になる。
# - 本流から外した語は 保留(held)・重複(duplicated)・不要(rejected) に置く。
#   保留は仕分けの画面の末尾に並び、いつでも決め直せる。
#   不要にした語も消さずに残し、表層形のユニーク制約で「一度見た語」の集合を兼ねる
#   (同じ語が expand / harvest から再流入したとき、取り込み時に弾けるようにするため)。
class WordCandidate < ApplicationRecord
  MAX_SURFACE_LENGTH = 255
  MAX_NOTE_LENGTH = 1000
  # 確信度の語彙。AnnotationProposal::HIGH_CONFIDENCE・LOW_CONFIDENCE と同じ(どちらも Claude の調査スキルの出力)。
  CONFIDENCES = %w[high medium low].freeze
  # notation の立項スコアがこれ以下の語は「立項に疑義がある語」として、確認のときに保留を選んでおく
  # (word-notation-research が上部リストから外す基準と同じ)。
  DOUBTFUL_ENTRY_SCORE = 2

  # 値は流れの順に並べ、間を空けておく(段を差し込めるように)。30 は旧 duplicate の段で、いまは使わない。
  enum :status, {
    triage: 10, expanding: 20, notating: 40, notated: 45, ready: 50, registered: 60,
    held: 80, duplicated: 85, rejected: 90
  }, validate: true

  # 前処理の段(STAGES の 1 行)。
  Stage = Data.define(:key, :statuses, :route, :export, :waiting, :choices) do
    # 段の見出しで「確認待ち N」として件数に添えるステータス。スキルに渡す段にいて、スキルを待っていない語
    # (表記の段の notated。/notation の結果が戻り、画面での確認を待つ語)。スキルに渡さない段は空。
    # 空でない段は、文言 admin.word_candidates.stages.<key>.reviewing を持つ。
    def reviewing_statuses = waiting ? statuses - [ waiting ] : []
  end

  # 前処理の4段(流れの順)。段ごとの決まりはこの表だけに置き、段の見出し(WordCandidatesHelper)・
  # 各段の画面(Admin::Candidates::*)・スキルへの書き出し(WordCandidateExport)・確認の一覧(WordCandidateReview)が引く。
  #   key      : 段の名前(i18n の admin.word_candidates.stages.<key>。段の見出しの現在地)
  #   statuses : その段にいる語のステータス(段の見出しの件数。4段を合わせたものが in_progress)
  #   route    : 段の画面のルート名(パスは <route>_path)
  #   export   : スキルへの書き出しのキー(WordCandidateExport::TARGETS。書き出しの textarea の name にもなる)。
  #              登録待ちの段だけは、段の名前ではなく渡す先のスキルの名前 "reading"。書き出さない段は nil
  #   waiting  : 書き出してスキルの結果を待つ語のステータス(拡張・表記は、取り込んだあとに残りの語数を知らせる)
  #   choices  : 画面で語ごとに選んで確定する処理。拡張は、まだ誰も判断していない語(仕分け)にだけ出す。確定の無い段は空
  # 表に入れないもの(各段のコントローラに置く): 確定で動かす語のステータス(画面に並べた一覧と同じにするので、
  # 一覧を組むコントローラに置く)と、確定のあとに開く画面(どの段を先に見せるかは、画面ごとの導線の判断なので)。
  STAGES = [
    Stage.new(key: "triage", statuses: %w[triage], route: :admin_candidates_triage,
              export: nil, waiting: nil, choices: %w[expand keep hold reject]),
    Stage.new(key: "expand", statuses: %w[expanding], route: :admin_candidates_expansion,
              export: "expand", waiting: "expanding", choices: []),
    Stage.new(key: "notation", statuses: %w[notating notated], route: :admin_candidates_notation,
              export: "notation", waiting: "notating", choices: %w[keep hold reject]),
    Stage.new(key: "ready", statuses: %w[ready], route: :admin_candidates_registration,
              export: "reading", waiting: "ready", choices: [])
  ].index_by(&:key).freeze

  # 「すべての語」の一覧でまとめて移せる先(本流から外した語を戻す・外すのに使う)。
  MOVES = %w[triage held rejected].freeze

  # まだ手が離れていない語(4段のどれかにいる語。保留は「あとで決める」と外した語なので、どの段にも入れていない)。
  scope :in_progress, -> { where(status: STAGES.values.flat_map(&:statuses)) }
  # 元の語の直後に、expand で増えた語が並ぶ順(upload した順を保つ)。
  scope :in_tree_order, -> { order(Arel.sql("COALESCE(word_candidates.root_id, word_candidates.id), word_candidates.id")) }
  # 表層形(いまの表記・upload した時点の表記)の部分一致。照合順序 as_ci なので、かなの種類・大小文字は問わない。
  scope :matching, ->(query) {
    pattern = "%#{sanitize_sql_like(query)}%"
    where("word_candidates.surface LIKE :pattern OR word_candidates.original_surface LIKE :pattern", pattern: pattern)
  }

  belongs_to :seed, class_name: "WordCandidate", optional: true
  belongs_to :root, class_name: "WordCandidate", optional: true
  belongs_to :word, optional: true
  has_many :expansions, class_name: "WordCandidate", foreign_key: :seed_id, inverse_of: :seed, dependent: :nullify

  validates :surface, presence: true, length: { maximum: MAX_SURFACE_LENGTH }, uniqueness: true
  validates :note, length: { maximum: MAX_NOTE_LENGTH }
  validates :entry_score, numericality: { only_integer: true, in: AnnotationProposal::ENTRY_SCORE_RANGE }, allow_nil: true
  validates :confidence, inclusion: { in: CONFIDENCES }, allow_nil: true

  before_validation :normalize_surface
  before_save :stamp_status_changed_at, if: :will_save_change_to_status?

  # 一括登録で語が収録されたら、同じ表層形の登録予定単語を「登録済み」にして語と結び付ける。
  # 一括登録の step2・3 は表層形を編集させない(hidden で持ち回す)ため、表層形の一致で取りこぼさない。
  def self.register_for!(word)
    where(surface: word.surface).where.not(status: :registered).find_each do |candidate|
      candidate.update!(status: :registered, word: word)
    end
  end

  # メモに追記する(調査の注記を取り込むたびに消さずに積む)。上限を超える分は切り詰める。
  def self.append_note(note, addition)
    [ note.presence, addition.to_s.strip.presence ].compact.join(" / ").truncate(MAX_NOTE_LENGTH).presence
  end

  # 追加・取り込みで語を入れられなかった理由(行のエラーに添える)。検証エラーはその内容、
  # 一意制約の違反は、先頭 191 字(prefix index)だけが既存の語と同じ長い語(検証をすり抜ける唯一の形)。
  def self.save_error_message(error)
    return error.record.errors.full_messages.join("、") if error.is_a?(ActiveRecord::RecordInvalid)

    I18n.t("admin.word_candidates.not_unique")
  end

  # 選んだ処理(段の choices の値)の行き先。除外は照合で一致があれば重複、無ければ不要。
  # 採用は、表記を確かめ済みの語(保留から戻した語など)なら登録待ち、まだなら表記待ちへ進める。
  def destination_for(decision, duplicate: false)
    case decision
    when "expand" then "expanding"
    when "keep" then notated_at ? "ready" : "notating"
    when "hold" then "held"
    when "reject" then duplicate ? "duplicated" : "rejected"
    end
  end

  # upload したままの語か: /expand で集めた語・分割でできた語ではなく、拡張も表記もまだの元の語
  # (仕分けで最初から拡張を選んでおく語。拡張の元にした語・集めた語は、拡張し直さないので含めない)。
  def fresh_upload?
    seed_id.nil? && expanded_at.nil? && notated_at.nil?
  end

  # 表層形が upload(または expand)で入った時点から変わったか(表記の確認で「元の表記」を添えるため)。
  def surface_changed_since_intake?
    original_surface.present? && original_surface != surface
  end

  # 立項スコアが低く、立項に疑義があるとされた語か。
  def doubtful_entry?
    entry_score.present? && entry_score <= DOUBTFUL_ENTRY_SCORE
  end

  # この語から expand で増やす語に持たせる属性(元の語と、系統の根)。
  def expansion_attributes
    { seed: self, root_id: root_id || id }
  end

  private

  # 表層形は textarea 貼り付けで改行が混ざりうる。内部の既存スペース(例「Dead by Daylight」)は
  # 語の一部なので保持する(Word#strip_surface_newlines と同じ扱い)。
  # upload した時点の表記は、notation で置き換わっても辿れるよう original_surface に残す。
  def normalize_surface
    self.surface = surface.gsub(/[\r\n]+/, " ").strip if surface
    self.original_surface ||= surface
  end

  def stamp_status_changed_at
    self.status_changed_at = Time.current
  end
end
