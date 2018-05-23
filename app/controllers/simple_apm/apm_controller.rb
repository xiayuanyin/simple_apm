require_dependency "simple_apm/application_controller"

module SimpleApm
  class ApmController < ApplicationController
    before_action :set_query
    helper_method :request_info
    def index
      @slow_requests = @query.all_slow_requests(20)
    end

    def show
      @info = @query.get_request_info(params[:id])
      @sqls = @query.get_request_sqls(params[:id]).sort_by{|x|x['started']}
    end

    def action_info
      @info = @query.get_action_info(params[:action_name])
      @slow_requests = @query.action_slow_requests(params[:action_name])
    end

    def change_date
      session[:apm_date] = params[:date]
      redirect_to request.referer
    end

    def request_info(id)
      @query.get_request_info(id)
    end

    private
    def set_query
      @query = SimpleApm::Query.new(get_date)
    end

    def get_date
      @apm_date ||= (session[:apm_date].present? ? Time.parse(session[:apm_date]) : Time.now)
    end
  end
end
