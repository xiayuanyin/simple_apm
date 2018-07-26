require "simple_apm/setting"
require "simple_apm/redis"
require "simple_apm/engine"
require 'callsite'
require 'get_process_mem'
module SimpleApm
  # 订阅log ---- start ----
  ActiveSupport::Notifications.subscribe('process_action.action_controller') do |name, started, finished, unique_id, payload|
    ProcessingThread.add_event(
        name: name,
        request_id: Thread.current['action_dispatch.request_id'],
        started: started, finished: finished,
        payload: payload,
        started_memory: Thread.current[:current_process_memory],
        completed_memory: GetProcessMem.new.mb
    )
    Thread.current['action_dispatch.request_id'] = nil
  end

  ActiveSupport::Notifications.subscribe 'sql.active_record' do |name, started, finished, unique_id, payload|
    request_id = Thread.current['action_dispatch.request_id'].presence || Thread.main['action_dispatch.request_id']
    if request_id
      if dev_caller = caller.detect {|c| c.include? Rails.root.to_s}
        c = ::Callsite.parse(dev_caller)
        payload.merge!(:line => c.line, :filename => c.filename.to_s.gsub(Rails.root.to_s, ''), :method => c.method)
      end
      ProcessingThread.add_event(
          name: name,
          request_id: request_id,
          started: started, finished: finished,
          payload: payload
      )
    end
  end
  # 订阅log ---- end ----


  # 开启一个接收事件的并行thread，每隔一秒处理一次
  class ProcessingThread
    class << self
      def add_event(e)
        @processing_thread && @processing_thread[:events].push(e)
      end
      def start!
        @main_thread ||= Thread.current
        @processing_thread ||= Thread.new do
          Thread.current.name = 'simple-apm-processing-thread'
          Thread.current[:events] ||= []
          loop do
            while e = Thread.current[:events].shift
              Worker.process! e
            end
            sleep 1
          end
        end
      end
    end
  end

  # 处理信息的操作方法
  class Worker
    class << self
      def process!(event)
        SimpleApm::RedisKey.query_date = nil
        if event[:name]=='process_action.action_controller'
          process_controller(event)
        elsif event[:name]=='sql.active_record'
          process_sql(event)
        end
      end

      private
      def process_controller(event)
        payload = event[:payload]
        started_memory = event[:started_memory]
        completed_memory = event[:completed_memory]
        finished = event[:finished]
        started = event[:started]
        request_id = event[:request_id]
        begin
          need_skip = payload[:controller] == 'SimpleApm::ApmController'
          need_skip = true if SimpleApm::Setting::EXCLUDE_ACTIONS.include?("#{payload[:controller]}##{payload[:action]}")
          need_skip = true if payload[:status].to_s=='302' && payload[:path].to_s=~/login/ && payload[:method].to_s.downcase=='get'

          if request_id.present?
            if need_skip
              SimpleApm::Sql.delete_by_request_id(request_id)
            else
              action_name = "#{payload[:controller]}##{payload[:action]}"
              memory_during = completed_memory - started_memory rescue 0
              info = {
                  request_id: request_id,
                  action_name: action_name,
                  url: payload[:path],
                  during: finished - started,
                  started: started.to_s,
                  db_runtime: payload[:db_runtime].to_f / 1000,
                  view_runtime: payload[:view_runtime].to_f / 1000,
                  controller: payload[:controller],
                  action: payload[:action],
                  host: Socket.gethostname,
                  remote_addr: (payload[:headers]['HTTP_X_REAL_IP'] rescue nil),
                  method: payload[:method],
                  completed_memory: completed_memory,
                  memory_during: memory_during,
                  format: payload[:format],
                  exception: payload[:exception].presence.to_json
              }.with_indifferent_access
              info[:status] = '500' if payload[:exception]
              # 存储
              in_slow = SimpleApm::SlowRequest.update_by_request info
              in_action_info = SimpleApm::Action.update_by_request info
              SimpleApm::Hit.update_by_request info
              if in_action_info || in_slow
                SimpleApm::Request.create info
              else
                SimpleApm::Sql.delete_by_request_id(request_id)
              end
            end
          end
        rescue => e
          Logger.new("#{Rails.root}/log/simple_apm.log").info e.backtrace.join("\n")
        end
      end

      def process_sql(event)
        payload = event[:payload]
        finished = event[:finished]
        started = event[:started]
        request_id = event[:request_id]
        begin
          during = finished - started
          if request_id.present? && ( SimpleApm::Setting::SQL_CRITICAL_TIME.blank? || during > SimpleApm::Setting::SQL_CRITICAL_TIME)
            # ActiveRecord::Relation::QueryAttribute
            sql_value = payload[:binds].map {|q| [q.name, q.value]} rescue nil
            info = {
                request_id: request_id,
                name: payload[:name],
                during: during,
                started: started,
                sql: payload[:sql],
                value: sql_value,
                filename: payload[:filename],
                line: payload[:line]
            }.with_indifferent_access
            SimpleApm::Sql.create request_id, info
          end
        rescue => e
          Logger.new("#{Rails.root}/log/simple_apm.log").info e.backtrace.join("\n")
        end
      end
    end
  end
end
