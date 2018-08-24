# 处理信息的操作方法
module SimpleApm
  class Worker
    class << self
      def process!(event)
        SimpleApm::RedisKey.query_date = nil
        if event[:name] == 'process_action.action_controller'
          process_controller(event)
        elsif event[:name] == 'sql.active_record'
          process_sql(event)
        elsif event[:name] == 'net_http.request'
          process_http_request(event)
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
        remote_addr = event[:remote_addr]
        net_http_during = event[:net_http_during]
        begin
          need_skip = payload[:controller] == 'SimpleApm::ApmController'
          need_skip = true if SimpleApm::Setting::EXCLUDE_ACTIONS.include?("#{payload[:controller]}##{payload[:action]}")
          need_skip = true if payload[:status].to_s == '302' && payload[:path].to_s =~ /login/ && payload[:method].to_s.downcase == 'get'

          if request_id.present?
            if need_skip
              SimpleApm::Sql.delete_by_request_id(request_id)
              SimpleApm::HttpRequest.delete_by_request_id(request_id)
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
                  remote_addr: remote_addr,
                  method: payload[:method],
                  completed_memory: completed_memory,
                  memory_during: memory_during,
                  format: payload[:format],
                  net_http_during: net_http_during,
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
                SimpleApm::HttpRequest.delete_by_request_id(request_id)
              end
            end
          end
        rescue => e
          ErrorLogger.log e.backtrace.join("\n")
        end
      end

      def process_sql(event)
        payload = event[:payload]
        finished = event[:finished]
        started = event[:started]
        request_id = event[:request_id]
        begin
          during = finished - started
          if request_id.present? && (SimpleApm::Setting::SQL_CRITICAL_TIME.blank? || during > SimpleApm::Setting::SQL_CRITICAL_TIME)
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
          ErrorLogger.log e.backtrace.join("\n")
        end
      end

      def process_http_request(event)
        payload = event[:payload]
        finished = event[:finished]
        started = event[:started]
        request_id = event[:request_id]
        begin
          during = finished - started
          if request_id.present?
            info = {
                request_id: request_id,
                name: payload[:name],
                during: during,
                started: started,
                url: payload[:url],
                host: payload[:host],
                path: payload[:path],
                filename: payload[:filename],
                line: payload[:line]
            }.with_indifferent_access
            SimpleApm::HttpRequest.create request_id, info
          end
        rescue => e
          ErrorLogger.log e.backtrace.join("\n")
        end
      end
    end
  end
end