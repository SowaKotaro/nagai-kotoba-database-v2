# タグ統括管理(Admin::TagsController)の表示ヘルパー。
module TagsHelper
  # 選択肢・一覧に出すタグの表示名。ジャンルは祖先を辿った階層パス(大 › 中 › 小)にして、
  # 同名の小分類でもどの系統か分かるようにする。index は N+1 回避用の id => Genre 索引。
  def tag_display_label(kind, record, index = nil)
    return record.name unless kind.hierarchical?

    genre_path_label(record, index)
  end

  # 統合の選択肢([表示名, id, 属性])。表示名に使用件数を添え(統合先を選ぶ目安)、
  # ジャンルは階層を data-level で渡す(tag_merge_controller.js が統合先を同じ階層に絞る)。
  # ジャンルは自分の名前を先頭に、親のパスを後ろに置く。選択肢は折り返せず、狭い幅では末尾が切れるので、
  # 「大 › 中 › 小」の順だと肝心の小分類の名前が見えなくなる。
  def tag_merge_options(kind, records, usage_counts, index = nil)
    records.map do |record|
      count = number_with_delimiter(usage_counts[record.id].to_i)
      label = t("admin.tags.merge.option", label: record.name, count: count)
      attributes = {}
      if kind.hierarchical?
        parent = record.parent_id && (index ? index[record.parent_id] : record.parent)
        label = t("admin.tags.merge.option_in_parent", option: label, parent: genre_path_label(parent, index)) if parent
        attributes = { data: { level: record.level } }
      end
      [ label, record.id, attributes ]
    end
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
    Genre.join_path(names)
  end
end
