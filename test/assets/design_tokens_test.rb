require "test_helper"

# 配色トークンの下限(CLAUDE.md / docs/design.md §6・§9)を tokens.css の値から確かめる。
#   - 文字は最も弱い --text-subtle でも、載りうる面の上で 4.5:1(WCAG AA)
#   - 選択中の面(--bg-tint)は、置かれる面(--surface)と ΔRGB 19 以上離す
# 色を変えたら実測する、という作法の取りこぼしを防ぐ(2026-09-23 まで、ダークの --bg-tint は差 11 だった)。
class DesignTokensTest < ActiveSupport::TestCase
  TOKENS = File.read(Rails.root.join("app/assets/stylesheets/tokens.css"))

  { "ライト" => "--", "ダーク" => "--dark-" }.each do |theme, prefix|
    test "#{theme}: --text-subtle はどの面の上でも 4.5:1 を満たす" do
      %w[surface bg bg-soft bg-tint].each do |face|
        ratio = contrast(token("#{prefix}text-subtle"), token("#{prefix}#{face}"))
        assert_operator ratio, :>=, 4.5, "#{theme}の --#{face} の上で #{ratio.round(2)}:1"
      end
    end

    test "#{theme}: 選択中の面(--bg-tint)は --surface と ΔRGB 19 以上離れている" do
      assert_operator delta_rgb(token("#{prefix}bg-tint"), token("#{prefix}surface")), :>=, 19
    end
  end

  private

  def token(name)
    TOKENS[/^\s*#{Regexp.escape(name)}:\s*(#\h{6})/, 1] or flunk "#{name} が tokens.css に無い"
  end

  def rgb(hex) = hex.delete("#").scan(/\h\h/).map { |pair| pair.to_i(16) }

  def delta_rgb(a, b) = rgb(a).zip(rgb(b)).sum { |x, y| (x - y).abs }

  def contrast(a, b)
    lighter, darker = [ luminance(a), luminance(b) ].sort.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  def luminance(hex)
    r, g, b = rgb(hex).map do |channel|
      c = channel / 255.0
      c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
    end
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end
end
