require_dependency "simple_apm/application_controller"

module SimpleApm
  class ApmController < ApplicationController
    include SimpleApm::ApplicationHelper
    before_action :set_query_date

    def dashboard
      d = SimpleApm::RedisKey.query_date == Time.now.strftime('%Y-%m-%d') ? Time.now.strftime('%H:%M') : '23:50'
      data = SimpleApm::Hit.chart_data(0, d)
      hits = data.values.sum { |point| point[:hits].to_i }
      time = data.values.sum { |point| point[:time].to_f }
      @daily_stats = {hits: hits, time: time, avg_time: hits.zero? ? 0 : time / hits}
      @x_names = data.keys.sort
      @time_arr = @x_names.map {|n| data[n][:hits].to_i.zero? ? 0 : (data[n][:time].to_f / data[n][:hits].to_i).round(3)}
      @hits_arr = @x_names.map {|n| data[n][:hits] rescue 0}
    end

    def index
      @sample_limit = [[(params[:count].presence || 200).to_i, 1].max, SimpleApm::Setting::SLOW_ACTIONS_LIMIT.to_i].min
      respond_to do |format|
        format.json do
          @slow_requests = SimpleApm::SlowRequest.list(@sample_limit).map do |r|
            request = r.request
            next unless request
            [
              link_to(time_label(request.started), show_path(id: request.request_id, apm_date: apm_date)),
              link_to(request.action_name, action_info_path(action_name: request.action_name, apm_date: apm_date)),
              duration_cell(request.during),
              duration_cell(request.db_runtime),
              request.queries_count,
              duration_cell(request.view_runtime),
              duration_cell(request.net_http_during),
              request.memory_during.to_f.round(1),
              ERB::Util.html_escape(request.host),
              ERB::Util.html_escape(request.remote_addr)
            ]
          end.compact
          render json: {data: @slow_requests}
        end
        format.html
      end
    end

    def show
      @request = SimpleApm::Request.find(params[:id])
      render :missing, status: :not_found unless @request
    end

    def actions
      @actions = SimpleApm::Action.all_names.map {|n| SimpleApm::Action.find(n)}
    end

    def action_info
      @action = SimpleApm::Action.find(params[:action_name])
      render :missing, status: :not_found if @action.click_count.to_i.zero?
    end

    def change_date
      session[:apm_date] = params[:date]
      redirect_to request.referer
    end

    def set_locale
      session[:simple_apm_locale] = params[:locale] if AVAILABLE_LOCALES.include?(params[:locale])
      redirect_back fallback_location: dashboard_path
    end

    def data
      @data = SimpleApm::Redis.in_apm_days.map {|x| SimpleApm::Hit.day_info(x)}
    end

    def data_delete
      if params[:date].is_a?(String)
        r = SimpleApm::Redis.clear_data(params[:date])
        flash[:notice] = r[:success] ? t("simple_apm.flash.deleted") : t("simple_apm.flash.no_data_for_day")
      elsif params[:type]=='month'
        del_count = SimpleApm::Redis.clear_data_before_time(Time.now.at_beginning_of_day - 1.month)
        flash[:notice] = t("simple_apm.flash.deleted_count", count: del_count)
      elsif params[:type]=='week'
        del_count = SimpleApm::Redis.clear_data_before_time(Time.now.at_beginning_of_day - 1.week)
        flash[:notice] = t("simple_apm.flash.deleted_count", count: del_count)
      elsif params[:type]=='stop_data'
        SimpleApm::Redis.stop!
        flash[:notice] = t("simple_apm.flash.updated")
      elsif params[:type]=='rerun_data'
        SimpleApm::Redis.rerun!
        flash[:notice] = t("simple_apm.flash.updated")
      else
        flash[:notice] = t("simple_apm.flash.unknown_action")
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
      helpers.link_to(name, url)
    end

    def duration_cell(seconds)
      helpers.content_tag(:span, sec_str(seconds), data: {seconds: seconds.to_f})
    end
  end
end
