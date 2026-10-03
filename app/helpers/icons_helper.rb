module IconsHelper
  # Phosphor Icons(Light ウェイト・MIT ライセンス)をインライン SVG で描画する。
  # fill: currentColor なので、親の color(文字色のトークン。管理画面では --admin-accent も)がそのまま効く。
  # CDN もアイコンフォントも使わない。
  # 出典/ライセンスは NOTICE(vendor/PHOSPHOR-LICENSE)を参照。
  def icon(name, css = nil)
    render "shared/icons/#{name}", class: css
  end
end
