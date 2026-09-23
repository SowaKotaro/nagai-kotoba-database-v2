# 登録予定単語の重複チェック(duplicate の段で使う)。
#
# この段ではまだ読みが無く(本番に MeCab も無い)、一括登録 step3 の読みベースの判定は使えない。
# そこで表層形を「粗く」畳んで照合するふるいに徹する: かなの種類・全角半角・大小文字を同一視し、
# 空白・中黒・記号を無視する(「ゴールドマンサックス」と「ゴールドマン・サックス」を同じ語とみなす)。
# 読みでの厳密な照合は、従来どおり一括登録 step3 が担う。
#
# 照合の相手は 収録済みの語(表層形・別表記) と ほかの登録予定単語(状態を問わない)。
class WordCandidateDuplicateCheck
  # 一致した相手。kind は :word(収録済みの語) / :variant(収録済みの語の別表記) / :candidate(ほかの登録予定単語)。
  Match = Struct.new(:kind, :surface, :word_id, :candidate, keyword_init: true)

  # 空白・句読点・記号(中黒・感嘆符・括弧など)。長音符「ー」は文字(Lm)なので残る。
  IGNORED_CHARACTERS = /[\p{P}\p{S}\p{Z}\s]/

  # 照合用に表層形を畳む。かなの寄せ方は公開側の重複チェックと揃える。
  def self.key(surface)
    WordRequestDuplicateCheck.fold(surface).downcase.gsub(IGNORED_CHARACTERS, "")
  end

  def initialize(candidates = [])
    @candidates = Array(candidates)
  end

  # { 候補の id => [Match, ...] }。一致の無い候補は空配列。
  def call
    @candidates.to_h { |candidate| [ candidate.id, matches_for(candidate.surface, except: candidate) ] }
  end

  # 表層形 surface に一致する相手。except の候補自身は含めない
  # (表記調査の取り込みで「置き換え後の表記」を照合するときにも使う)。
  def matches_for(surface, except: nil)
    matches = corpus.fetch(self.class.key(surface), []).reject { |match| except && match.candidate&.id == except.id }
    # 表層形と別表記の両方で同じ語に当たることがあるため、相手1件につき1行に畳む(表層形を優先)。
    matches.uniq { |match| match.candidate ? [ :candidate, match.candidate.id ] : [ :word, match.word_id ] }
  end

  # 照合を続けながら候補を足す・表記を変えたとき、以降の照合に新しい表層形を反映する。
  def register(candidate)
    corpus[self.class.key(candidate.surface)] << Match.new(kind: :candidate, surface: candidate.surface, candidate: candidate)
  end

  private

  # 畳んだ表層形 => 一致の相手。収録語・別表記・登録予定単語を1回ずつ読み込む(管理画面専用で、件数は数千語規模)。
  def corpus
    @corpus ||= Hash.new { |hash, key| hash[key] = [] }.tap do |index|
      Word.pluck(:id, :surface).each do |id, surface|
        index[self.class.key(surface)] << Match.new(kind: :word, surface: surface, word_id: id)
      end
      WordSenseVariant.joins(:word_sense).pluck("word_senses.word_id", "word_sense_variants.surface").each do |id, surface|
        index[self.class.key(surface)] << Match.new(kind: :variant, surface: surface, word_id: id)
      end
      WordCandidate.find_each do |candidate|
        index[self.class.key(candidate.surface)] << Match.new(kind: :candidate, surface: candidate.surface, candidate: candidate)
      end
    end
  end
end
