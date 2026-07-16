# 提案の「新設候補」マスタを1つ作成する(Issue 66)。コンソールの提案パネルの作成ボタンから
# 呼ばれ、作成後に提案を再反映すると解決してフォームに入る。field で種別を絞り、未知の名前だけを
# その場でマスタ化する(ジャンルは既存の木で解決できた中分類の下に小分類を作る)。
class ProposedMasterCreation
  Error = Class.new(StandardError)

  FIELDS = %w[entity_type part_of_speech word_origin genre].freeze

  # sense_proposal: AnnotationProposal::SenseProposal(提案名の供給元)
  # field: 作成する種別 / name: 語種のように候補が複数ある種別で、作る名前を明示する
  def initialize(sense_proposal, field, name = nil)
    @sense = sense_proposal
    @field = field
    @name = name
  end

  # 作成した(または既存の)マスタを返す。作成できない指定は Error を投げる。
  def create!
    raise Error, "unknown field: #{@field}" unless FIELDS.include?(@field)

    case @field
    when "entity_type"    then create_named(EntityType, @sense.entity_type_name)
    when "part_of_speech" then create_named(PartOfSpeech, @sense.part_of_speech_name)
    when "word_origin"    then create_named(WordOrigin, @name)
    when "genre"          then create_genre_small
    end
  end

  private

  def create_named(model, name)
    raise Error, "blank name" if name.blank?

    model.find_or_create_by!(name: name)
  end

  # 提案の小分類名を、既存の木で解決できた中分類の下に作る(level は明示。genre-picker の
  # その場追加と同じ規則)。中分類まで解決していなければ親が決まらないので作れない。
  def create_genre_small
    medium = @sense.resolved_genre_chain.last
    raise Error, "medium genre unresolved" unless medium&.medium?

    small_name = @sense.genre_path[2]
    raise Error, "blank small genre" if small_name.blank?

    Genre.find_or_create_by!(name: small_name, parent: medium) { |genre| genre.level = :small }
  end
end
