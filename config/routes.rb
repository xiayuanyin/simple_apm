SimpleApm::Engine.routes.draw do
  get 'dashboard', to: 'apm#dashboard'
  get 'index', to: 'apm#index'
  get 'show', to: 'apm#show'
  get 'action_info', to: 'apm#action_info'
  get 'actions', to: 'apm#actions'
  get 'set_apm_date', to: 'apm#set_apm_date'

end
