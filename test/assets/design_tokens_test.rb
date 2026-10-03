require "test_helper"

# 配色トークンの下限(CLAUDE.md / docs/design.md §6・§9)を tokens.css の値から確かめる。
#   - 文字は最も弱い --text-subtle でも、載りうる面の上で 4.5:1(WCAG AA)
#   - 選択中の面(--bg-tint)は、置かれる面(--surface)と ΔRGB 19 以上離す
# 色を変えたら実測する、という作法の取りこぼしを防ぐ(2026-09-23 まで、ダークの --bg-tint は合計の差で 11 だった)。
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

  # ダークの適用は「OS 設定に追従する @media」と「トグルで付く [data-theme="dark"]」の 2 ブロックに
  # 同じ中身を書いている。片方だけに足すと、その経路でだけダークの色が抜ける。
  test "ダークの 2 ブロックは同じ宣言を持ち、--dark-* のトークンをすべて参照する" do
    media = declarations(TOKENS[/@media \(prefers-color-scheme: dark\) \{\s*:root:not\(\[data-theme="light"\]\) \{(.*?)\}/m, 1])
    toggle = declarations(TOKENS[/:root\[data-theme="dark"\] \{(.*?)\}/m, 1])

    assert_equal media, toggle
    dark_tokens = TOKENS.scan(/^\s*--dark-([\w-]+):/).flatten
    assert_equal dark_tokens.to_h { |name| [ "--#{name}", "var(--dark-#{name})" ] },
                 media.reject { |name, _| name == "color-scheme" }
    assert_equal "dark", media["color-scheme"]
  end

  # 同じ特異度の規則は後に書いた方が勝つので、読み込み順そのものが見た目を決めている(application.css の冒頭)。
  test "application.css は tokens → base → layout → components → annotate → candidates → admin の順に読む" do
    manifest = File.read(Rails.root.join("app/assets/stylesheets/application.css"))
    assert_equal %w[tokens base layout components annotate candidates admin], manifest.scan(/^\s*\*= require (\w+)$/).flatten
    assert_match(/^\s*\*= require_self$/, manifest)
    assert_no_match(/require_tree/, manifest.lines.grep(/^\s*\*=/).join)
  end

  private

  # ブロックの中の宣言を { 名前 => 値 } にする。
  def declarations(block)
    flunk "ダークのブロックが tokens.css に見つからない" unless block
    block.scan(/^\s*([\w-]+):\s*([^;]+);/).to_h
  end

  def token(name)
    TOKENS[/^\s*#{Regexp.escape(name)}:\s*(#\h{6})/, 1] or flunk "#{name} が tokens.css に無い"
  end

  def rgb(hex) = hex.delete("#").scan(/\h\h/).map { |pair| pair.to_i(16) }

  # いまは差の合計で測っている。docs/design.md §1 の定義(R・G・B の差の最大値)とは違う(既知の問題。
  # 最大差にするとダークの --bg-tint が 16 で落ちるので、式を直すときは色の判断と一緒に行う)。
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
