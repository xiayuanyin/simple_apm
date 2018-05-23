SimpleApm::Engine.routes.draw do
  get 'index', to: 'apm#index'
  get 'show', to: 'apm#show'
  get 'action_info', to: 'apm#action_info'

end
