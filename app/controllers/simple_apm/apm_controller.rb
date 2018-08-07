require_dependency "simple_apm/application_controller"

module SimpleApm
  class ApmController < ApplicationController
    include SimpleApm::ApplicationHelper
    before_action :set_query_date

    def dashboard
      d = SimpleApm::RedisKey.query_date == Time.now.strftime('%Y-%m-%d') ? Time.now.strftime('%H:%M') : '23:50'
      data = SimpleApm::Hit.chart_data(0, d)
      @x_names = data.keys.sort
      @time_arr = @x_names.map {|n| data[n][:hits].to_i.zero? ? 0 : (data[n][:time].to_f / data[n][:hits].to_i).round(3)}
      @hits_arr = @x_names.map {|n| data[n][:hits] rescue 0}
    end

    def index
      respond_to do |format|
        format.json do
          @slow_requests = SimpleApm::SlowRequest.list(params[:count] || 200).map do |r|
            request = r.request
            [
              link_to(time_label(request.started), show_path(id: request.request_id)),
              link_to(request.action_name, action_info_path(action_name: request.action_name)),
              sec_str(request.during),
              sec_str(request.db_runtime),
              sec_str(request.view_runtime),
              sec_str(request.net_http_during),
              request.memory_during.to_f.round(1),
              request.host,
              request.remote_addr
            ]
          end
          render json: {data: @slow_requests}
        end
        format.html
      end
    end

    def show
      @request = SimpleApm::Request.find(params[:id])
    end

    def actions
      @actions = SimpleApm::Action.all_names.map {|n| SimpleApm::Action.find(n)}
    end

    def action_info
      @action = SimpleApm::Action.find(params[:action_name])
    end

    def change_date
      session[:apm_date] = params[:date]
      redirect_to request.referer
    end

    def data
      @data = SimpleApm::Redis.in_apm_days.map {|x| SimpleApm::Hit.day_info(x)}
    end

    def data_delete
      if params[:date].is_a?(String)
        r = SimpleApm::Redis.clear_data(params[:date])
        flash[:notice] = r[:success] ? '删除成功！' : r[:msg]
      elsif params[:type]=='month'
        del_count = SimpleApm::Redis.clear_data_before_time(Time.now.at_beginning_of_day - 1.month)
        flash[:notice] = "成功删除#{del_count}条数据"
      elsif params[:type]=='week'
        del_count = SimpleApm::Redis.clear_data_before_time(Time.now.at_beginning_of_day - 1.week)
        flash[:notice] = "成功删除#{del_count}条数据"
      elsif params[:type]=='stop_data'
        SimpleApm::Redis.stop!
        flash[:notice] = '设置成功！'
      elsif params[:type]=='rerun_data'
        SimpleApm::Redis.rerun!
        flash[:notice] = '设置成功！'
      else
        flash[:notice] = '未知操作！'
        # r = params[:date].map{|d|SimpleApm::Redis.clear_data(d)}
        # suc, fail = r.partition{|x|x[:success]}
        # flash[:notice] = "成功删除#{suc.length}"
        # flash[:notice] << "，失败#{fail.length}" if fail.length>0
      end
      redirect_to action: :data
    end

    def set_apm_date
      # set_query_date
      redirect_to action: :dashboard
    end

    private

    def set_query_date
      session[:apm_date] = params[:apm_date] if params[:apm_date].present?
      SimpleApm::RedisKey.query_date = session[:apm_date]
    end

    def link_to(name, url)
      "<a href=#{url.to_json}>#{name}</a>"
    end
  end
end
