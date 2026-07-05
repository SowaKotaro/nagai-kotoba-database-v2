# 本番のジャンルマスタに残った「旧名(第X類：…)」の重複大分類とそのサブツリーを掃除する一回限りのタスク。
#
# 背景: 大分類名から「第X類：」を除去した際、seed は find_or_create_by!(name:) で
# 名前照合するため旧レコードが消えず、デプロイ時の db:seed で新名が新規作成され二重化した。
# 旧サブツリー(大・中のみ。word_senses が指す小分類は含まない)を安全に削除する。
#
# 使い方(本番, release_path 内で):
#   RAILS_ENV=production bundle exec rails genres:cleanup_dupes          # ドライラン(表示のみ)
#   RAILS_ENV=production bundle exec rails genres:cleanup_dupes APPLY=1  # 実削除
#
# 冪等: 実行後に対象が無くなれば以降は何も削除しない。
namespace :genres do
  # 旧名の目印。過去 seed の大分類は「第0類：」「第1類：」… という接頭辞を持っていた。
  STALE_LARGE_NAME = /\A第\d+類：/

  desc "旧名(第X類：)の重複大分類サブツリーを削除する。既定はドライラン。APPLY=1 で実削除。"
  task cleanup_dupes: :environment do
    apply = ENV["APPLY"] == "1"

    stale_larges = Genre.large.where("name REGEXP ?", "^第[0-9]+類：")
    if stale_larges.empty?
      puts "旧名(第X類：)の大分類は見つかりませんでした。掃除は不要です。"
      puts "現在の件数: 大分類#{Genre.large.count}件 / 中分類#{Genre.medium.count}件 / 小分類#{Genre.small.count}件"
      next
    end

    # 削除対象サブツリー(旧大分類 + その全子孫)の id を集める。
    target_ids = []
    stale_larges.find_each do |large|
      subtree = collect_subtree_ids(large)
      target_ids.concat(subtree)
    end
    target_ids.uniq!

    # 安全確認: word_senses から参照されている id が混じっていないか(混じれば FK で失敗する)。
    referenced = WordSense.where(genre_id: target_ids).distinct.pluck(:genre_id)
    if referenced.any?
      puts "中止: 削除対象のジャンルが word_senses から参照されています(id: #{referenced.sort.join(', ')})。"
      puts "先に該当語義のジャンルを付け替えてから再実行してください。"
      next
    end

    puts "削除対象の旧大分類: #{stale_larges.count}件"
    stale_larges.order(:id).each do |g|
      child_count = Genre.where(parent_id: g.id).count
      puts "  - ##{g.id} #{g.name}(中分類#{child_count}件)"
    end
    puts "削除対象レコード総数(大+中): #{target_ids.size}件"

    unless apply
      puts "\n[ドライラン] 実際には削除していません。APPLY=1 を付けて再実行すると削除します。"
      next
    end

    ActiveRecord::Base.transaction do
      # 子(中分類)を先に消してから親(大分類)を消す。restrict_with_error を避けるため id 直指定で delete。
      Genre.where(id: target_ids).where.not(parent_id: nil).delete_all
      Genre.where(id: target_ids).delete_all
    end

    puts "\n削除しました。"
    puts "現在の件数: 大分類#{Genre.large.count}件 / 中分類#{Genre.medium.count}件 / 小分類#{Genre.small.count}件"
  end

  # 与えた大分類ノードの id と全子孫 id を配列で返す(隣接リストを幅優先で辿る)。
  def collect_subtree_ids(root)
    ids = [ root.id ]
    frontier = [ root.id ]
    until frontier.empty?
      children_ids = Genre.where(parent_id: frontier).pluck(:id)
      ids.concat(children_ids)
      frontier = children_ids
    end
    ids
  end
end
