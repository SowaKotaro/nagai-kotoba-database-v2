Rails.application.routes.draw do
  resource :session

  # 公開閲覧(誰でも閲覧可)。一覧・詳細のみ。書き込みは admin 名前空間に閉じる。
  resources :words, only: %i[index show]
  # 公開の検索。簡素(キーワードのみ)と詳細(全条件)の2段構え。
  get "search/simple", to: "searches#simple", as: :simple_search
  get "search", to: "searches#index", as: :search

  # 管理者専用の登録・編集・削除。認証必須(Admin::BaseController)。
  namespace :admin do
    # 詳細(show)は公開閲覧側(Issue 8)で扱うため管理側には持たせない。
    resources :words, except: :show
    # 高速アノテーション・コンソール(1語集中キュー)。index は最初の未注釈へ誘導。
    resources :annotations, only: %i[index show update]
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
