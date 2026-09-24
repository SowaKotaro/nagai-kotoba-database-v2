# 仕分け・表記の確認の画面に並べる語の一覧。行ごとに 照合結果・初期の選択・印 を持ち、系統ごとに括る。
#
# 初期の選択は「何も触らずに確定したらこうなる」を表す。オーナーは例外の行だけを選び直して確定する
# (300語を1語ずつチェックさせないため)。
#   仕分け(:triage)    : 保留にしていた語は保留 / 照合で一致した語は除外 / それ以外は採用
#   表記の確認(:notation): 照合で一致した語は除外 / 立項に疑義がある語は保留 / それ以外は採用
class WordCandidateReview
  # 画面ごとに選べる処理(WordCandidate::DECISIONS の部分集合)。拡張は、まだ誰も判断していない語にだけ出す。
  CHOICES = { triage: %w[expand keep hold reject], notation: %w[keep hold reject] }.freeze

  # 行の印(絞り込みのボタンに出す順)。重複の疑い / 表記が変わった / 立項に疑義。
  FLAGS = %w[duplicate changed doubtful].freeze

  # 行。default は初期の選択、flags は FLAGS のうち当てはまる印。
  Row = Struct.new(:candidate, :matches, :default, :flags, keyword_init: true)

  # 系統(同じ元の語から expand・分割で増えた語)のまとまり。root はその系統の元の語(一覧に無いこともある)。
  Group = Struct.new(:root, :rows, keyword_init: true) do
    # 括って見せるか。元の語1語だけの行は括らない(upload しただけの語が大半なので、見出しを増やさない)。
    def family?
      rows.size > 1 || rows.first.candidate != root
    end

    def root_row?(row)
      row.candidate == root
    end
  end

  attr_reader :context

  def initialize(candidates, context:)
    @candidates = candidates.to_a
    @context = context
  end

  def choices
    CHOICES.fetch(context)
  end

  def size
    @candidates.size
  end

  def empty?
    @candidates.empty?
  end

  def rows
    @rows ||= begin
      matches = WordCandidateDuplicateCheck.new(@candidates).call
      @candidates.map { |candidate| build_row(candidate, matches.fetch(candidate.id)) }
    end
  end

  # 系統ごとのまとまり(並びは in_tree_order のまま。同じ系統の語は続けて並んでいる)。
  def groups
    @groups ||= begin
      chunks = rows.chunk_while { |a, b| family_id(a.candidate) == family_id(b.candidate) }.to_a
      roots = roots_for(chunks.map { |chunk| family_id(chunk.first.candidate) })
      chunks.map { |chunk| Group.new(root: roots.fetch(family_id(chunk.first.candidate)), rows: chunk) }
    end
  end

  # 印ごとの行数(絞り込みのボタンに添える)。
  def flag_counts
    rows.flat_map(&:flags).tally
  end

  private

  def family_id(candidate)
    candidate.root_id || candidate.id
  end

  # 系統の元の語。一覧に無い元の語(分割して不要にした語など)だけを読み足す。
  def roots_for(ids)
    listed = @candidates.index_by(&:id)
    listed.slice(*ids).merge(WordCandidate.where(id: ids - listed.keys).index_by(&:id))
  end

  def build_row(candidate, matches)
    flags = []
    flags << "duplicate" if matches.any?
    if context == :notation
      flags << "changed" if candidate.surface_changed_since_intake?
      flags << "doubtful" if candidate.doubtful_entry?
    end
    Row.new(candidate: candidate, matches: matches, flags: flags, default: default_for(candidate, flags))
  end

  def default_for(candidate, flags)
    return "hold" if candidate.held?
    return "reject" if flags.include?("duplicate")
    return "hold" if flags.include?("doubtful")

    "keep"
  end
end
