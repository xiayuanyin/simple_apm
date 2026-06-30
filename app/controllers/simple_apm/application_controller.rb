module SimpleApm
  class ApplicationController < ActionController::Base
    AVAILABLE_LOCALES = %w[en zh-CN].freeze

    protect_from_forgery with: :exception
    around_action :switch_simple_apm_locale
    helper_method :apm_date, :simple_apm_locale

    def apm_date
      session[:apm_date].presence || Time.now.strftime("%Y-%m-%d")
    end

    def simple_apm_locale
      locale = session[:simple_apm_locale].presence
      AVAILABLE_LOCALES.include?(locale) ? locale : "en"
    end

    private

    def switch_simple_apm_locale(&action)
      I18n.with_locale(simple_apm_locale, &action)
    end
  end
end
