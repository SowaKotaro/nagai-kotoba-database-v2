Rails.application.routes.draw do
  resource :session

  # 公開閲覧(誰でも閲覧可)。一覧・詳細のみ。書き込みは admin 名前空間に閉じる。
  resources :words, only: %i[index show]
  # 公開の詳細検索フォーム。キーワードだけの検索はヘッダー等から words#index の q で行う。
  get "search", to: "searches#index", as: :search

  # ジャンル階層のハブページ(全ジャンル面へのクロール導線)。Issue 21。
  resources :genres, only: :index

  # 50音・読みの文字数の索引(ブラウズ導線)。Issue 22。
  get "browse", to: "browse#index", as: :browse

  # 検索エンジン向けの sitemap(公開・注釈済みの全単語 + 静的ページ)。Issue 15。
  get "sitemap.xml", to: "sitemaps#show", defaults: { format: "xml" }, as: :sitemap

  # サイト概要・収録基準・利用条件などの恒久ページ。Issue 20。
  get "about", to: "pages#about", as: :about

  # LLM(AI 検索・エージェント)向けのサイト案内。Issue 24。
  get "llms.txt", to: "llms#show", defaults: { format: "text" }, as: :llms

  # robots.txt(動的)。Sitemap 行のホストを canonical_host と連動させる。
  get "robots.txt", to: "robots#show", defaults: { format: "text" }, as: :robots

  # 管理者専用の登録・編集・削除。認証必須(Admin::BaseController)。
  namespace :admin do
    # 管理コンソールのトップ(/admin)。登録・アノテーションへの入口。
    root "dashboard#index"
    # 詳細(show)は公開閲覧側(Issue 8)で扱う。編集はアノテーション・コンソールに統合済み(Issue 36)。
    # 一括登録は3ステップ: new(入力) → readings(step2 読み) → duplicates(step3 重複) → create(登録)。
    resources :words, only: %i[index new create destroy] do
      collection do
        post :readings
        post :apply_research
        post :duplicates
      end
    end
    # 一覧で選択した語への共通属性の一括適用(Issue 37)。
    resource :bulk_annotation, only: :create
    # Claude Code 連携(Issue 38): 調査用データの書き出しと、提案 JSON の取り込み。
    resources :annotation_proposals, only: %i[new create] do
      get :export, on: :collection
    end
    # 高速アノテーション・コンソール(1語集中キュー)。index は最初の未注釈へ誘導。
    resources :annotations, only: %i[index show update]
    # タグ統括管理: マスタ(ジャンル/エンティティ/品詞/語種/特徴)の一覧・リネーム・削除・統合。
    # :kind は TagKind のホワイトリストで解決する(任意モデルを掴ませない)。
    resources :tags, only: :index
    get    "tags/:kind",          to: "tags#show",    as: :tag_kind
    get    "tags/:kind/:id/edit", to: "tags#edit",    as: :edit_tag
    patch  "tags/:kind/:id",      to: "tags#update",  as: :tag
    # 削除は更新と同じパス(admin_tag_path)を DELETE で叩くため、ヘルパは作らない。
    delete "tags/:kind/:id",      to: "tags#destroy", as: nil
    # 統合は種別トップの1パネルで source→target を選ぶため :id を取らない。
    post   "tags/:kind/merge",    to: "tags#merge",   as: :merge_tags
    # ジャンルの大→中→小 依存選択用に、子ジャンルの取得と、その場での新規追加。
    resources :genres, only: :create do
      get :children, on: :collection
    end
    # マスタのその場追加(コンソールから画面遷移せずに選択肢を増やす)。
    resources :word_origins, only: :create
    resources :parts_of_speech, only: :create
    resources :entity_types, only: :create
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "home#index"
end
