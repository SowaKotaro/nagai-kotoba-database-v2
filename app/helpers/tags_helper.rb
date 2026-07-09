# タグ統括管理(Admin::TagsController)の表示ヘルパー。
module TagsHelper
  # 選択肢・一覧に出すタグの表示名。ジャンルは祖先を辿った階層パス(大 › 中 › 小)にして、
  # 同名の小分類でもどの系統か分かるようにする。index は N+1 回避用の id => Genre 索引。
  def tag_display_label(kind, record, index = nil)
    return record.name unless kind.hierarchical?

    genre_path_label(record, index)
  end

  # ジャンルの階層パス。index があれば親を辿るのに使い(追加クエリを出さない)、無ければ関連を辿る。
  def genre_path_label(genre, index = nil)
    names = [ genre.name ]
    node = genre
    while (parent_id = node.parent_id)
      node = index ? index[parent_id] : node.parent
      break unless node

      names.unshift(node.name)
    end
    names.join(" › ")
  end
end
