module IconsHelper
  # 向きや動きを持つアイコン。名前の修飾子(icon--arrow-right など)を付け、遊びの動き(motion.css)が
  # 矢印を向きへ進め、シャッフルの印をめくるのに使う。ほかのアイコンには修飾子を付けない(CSS の用途が無いため。
  # docs/design.md §11)
  MOTION_ICONS = %w[arrow_right arrow_left shuffle].freeze

  # Phosphor Icons(Light ウェイト・MIT ライセンス)をインライン SVG で描画する。
  # fill: currentColor なので、親の color(文字色のトークン。管理画面では --admin-accent も)がそのまま効く。
  # CDN もアイコンフォントも使わない。
  # 出典/ライセンスは NOTICE(vendor/PHOSPHOR-LICENSE)を参照。
  def icon(name, css = nil)
    modifier = "icon--#{name.to_s.dasherize}" if MOTION_ICONS.include?(name.to_s)
    render "shared/icons/#{name}", class: [ modifier, css ].compact.join(" ").presence
  end
end
