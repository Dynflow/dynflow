Dynflow::Engine.routes.draw do
  resources :plans do
    member do
      match 'resume' => 'plans#resume', :via => :post
      match 'skip_step/:step_id' => 'plans#skip_step', :via => :post
    end
  end
end
