Rails.application.routes.draw do
  mount SimpleApm::Engine => "/simple_apm"
end
