Rails.application.routes.draw do
  resource :session

  # 公開閲覧(誰でも閲覧可)。一覧・詳細のみ。書き込みは admin 名前空間に閉じる。
  resources :words, only: %i[index show]
  # 公開の検索・絞り込み。
  get "search", to: "searches#index", as: :search

  # 管理者専用の登録・編集・削除。認証必須(Admin::BaseController)。
  namespace :admin do
    # 詳細(show)は公開閲覧側(Issue 8)で扱うため管理側には持たせない。
    resources :words, except: :show
    # ジャンルの大→中→小 依存ドロップダウン用に、指定した親の子ジャンルを返す。
    resources :genres, only: [] do
      get :children, on: :collection
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "home#index"
end
