module SimpleApm
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    helper_method :apm_date

    def apm_date
      session[:apm_date].presence || Time.now.strftime("%Y-%m-%d")
    end
  end
end
