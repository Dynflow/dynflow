Rails.application.routes.draw do

  resources :users


  resources :events do
    member do
      match 'invite' => 'events#invite', :via => :get
      match 'process_invitation' => 'events#process_invitation', :via => :post
    end
  end


  mount Dynflow::Engine => "/dynflow"
end
