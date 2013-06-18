require 'dynflow/web_console'

Rails.application.routes.draw do

  resources :users


  resources :events do
    member do
      match 'invite' => 'events#invite', :via => :get
      match 'process_invitation' => 'events#process_invitation', :via => :post
    end
  end

  console = Dynflow::WebConsole.setup do
    set :bus, Dynflow::Bus
  end

  mount console => "/dynflow"
end
