# デザイン案のモック置き場(管理者のみ)。知人にデザインの方向性の意見を聞くための試作で、
# DB には一切触らない完全な静的ページ。表示データは Admin::DesignMocksHelper の固定値。
#
# ※この配下のビュー/CSS だけは docs/design.md のデザインルールを適用しない。
#   角丸・影・グラデーション・第二のアクセント色などを各案の様式どおりに使ってよい。
#   公開側・管理側の本体には影響しない(専用レイアウト design_mock + 専用 CSS design_mocks.css)。
class Admin::DesignMocksController < Admin::BaseController
  # モック本体(show)だけは共通ヘッダー/フッターと application.css を外した専用レイアウトで出す。
  layout -> { action_name == "show" ? "design_mock" : "application" }

  # 描画するテンプレートは params から組み立てず、この定数から引く(任意のテンプレートを掴ませない)。
  TEMPLATES = Admin::DesignMocksHelper::STYLES.keys.product(Admin::DesignMocksHelper::PAGES.keys)
                                              .to_h { |style, page| [ [ style, page ], "admin/design_mocks/#{style}/#{page}" ] }
                                              .freeze

  def index
  end

  def show
    @style = params[:style]
    @page  = params[:page]
    template = TEMPLATES[[ @style, @page ]]
    return head :not_found if template.nil?

    render template: template
  end
end
