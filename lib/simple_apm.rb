require "simple_apm/setting"
require "simple_apm/redis"
require "simple_apm/engine"
require "simple_apm/query"

module SimpleApm
  ActiveSupport::Notifications.subscribe('process_action.action_controller') do |name, started, finished, unique_id, payload|
    request_id = Thread.current['action_dispatch.request_id']
    date_str = Time.now.strftime('%Y-%m-%d')
    if request_id.present?
      action_name = "#{payload[:controller]}##{payload[:action]}.#{payload[:format]}"

      action_list_key = "#{date_str}:action-names"
      action_slow_key = "#{date_str}:action-slow:#{action_name}"
      request_key = "#{date_str}:requests"
      action_info_key = "#{date_str}:action-info:#{action_name}"
      hour_hits_key = "#{date_str}:hour-hits"
      slow_requests_key = "#{date_str}:slow-requests"
      during = finished - started

      info = {
        id: request_id,
        during: finished - started,
        started: started.to_s,
        db_runtime: payload[:db_runtime].to_f/1000,
        view_runtime: payload[:view_runtime].to_f/1000,
        controller: payload[:controller],
        action: payload[:action],
        host: Socket.gethostname,
        remote_addr: payload[:headers]['REMOTE_ADDR'],
        method: payload[:method],
        format: payload[:format],
        exception: payload[:exception].presence.to_json
      }
      info[:status] = '500' if payload[:exception]

      # 如果没有相关需要保存的则保存结束后移除相关信息
      need_remove_info = true

      # 每小时点击数
      SimpleApm::Redis.hincrby hour_hits_key, Time.now.hour, 1

      # 点击次数
      SimpleApm::Redis.hincrby action_info_key, 'click_count', 1
      # 总时间
      SimpleApm::Redis.hincrbyfloat action_info_key, 'time', during
      _slow = SimpleApm::Redis.hget action_info_key, 'slow_time'
      if _slow.nil? || during.to_f > _slow.to_f
        # 记录最慢访问
        SimpleApm::Redis.hmset action_info_key, 'slow_time', during, 'slow_id', request_id
        need_remove_info = false
      end
      _fast = SimpleApm::Redis.hget action_info_key, 'fast_time'
      if _fast.nil? || during.to_f < _fast.to_f
        # 记录最快访问
        SimpleApm::Redis.hmset action_info_key, 'fast_time', during, 'fast_id', request_id
        need_remove_info = false
      end


      # 列表增加action name
      SimpleApm::Redis.sadd(action_list_key, action_name)

      # 此action里最慢的100个请求列表
      SimpleApm::Redis.zadd(action_slow_key, during, request_id)
      SimpleApm::Redis.zremrangebyrank(action_slow_key, 0, -SimpleApm::Setting::ACTION_SLOW_REQUEST_LIMIT - 1)
      # 在慢action里有排名则保留
      if need_remove_info && SimpleApm::Redis.zrank(action_slow_key, request_id).present?
        need_remove_info = false
      end
      # 记录最慢请求列表1000个
      SimpleApm::Redis.zadd(slow_requests_key, during, request_id)
      SimpleApm::Redis.zremrangebyrank(slow_requests_key, 0, -SimpleApm::Setting::SLOW_ACTIONS_LIMIT - 1)
      if need_remove_info && SimpleApm::Redis.zrank(slow_requests_key, request_id).present?
        need_remove_info = false
      end

      # 当此次request不在列表里，则记录请求的基础信息
      SimpleApm::Redis.hmset request_key, request_id, info.to_json unless need_remove_info
      if need_remove_info
        SimpleApm::Redis.del "#{date_str}:sql:#{request_id}"
      end
    end
  rescue => e
    Logger.new("#{Rails.root}/log/simple_apm.log").info e.inspect
  end

  ActiveSupport::Notifications.subscribe 'sql.active_record' do |name, started, finished, unique_id, payload|
    request_id = Thread.current['action_dispatch.request_id'].presence||Thread.main['action_dispatch.request_id']
    if request_id.present?
      info_key = "apm:#{Time.now.strftime('%Y-%m-%d')}:sql:#{request_id}"
      dev_caller = caller.detect { |c| c.include? Rails.root.to_s }
      if dev_caller
        c = Callsite.parse(dev_caller)
        payload.merge!(:line => c.line, :filename => c.filename, :method => c.method)
      end
      info = {
        hash_code: payload[:sql].hash,
        name: payload[:name],
        during: finished - started,
        started: started,
        sql: payload[:sql],
        filename: payload[:filename],
        line: payload[:line],
        connection_id: payload[:connection_id],
        value: payload[:binds].map{|x|[x.name, x.value]}
      }
      SimpleApm::Redis.rpush(info_key, info.to_json)
    end
  rescue => e
    Logger.new("#{Rails.root}/log/simple_apm.log").info e.inspect
  end
end
