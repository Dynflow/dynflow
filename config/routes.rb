Dynflow::Engine.routes.draw do
  resources :journals do
    member do
      match 'resume' => 'journals#resume', :via => :post
      match 'rerun_item/:journal_item_id' => 'journals#rerun_item', :via => :post
      match 'skip_item/:journal_item_id' => 'journals#skip_item', :via => :post
    end
  end
end
