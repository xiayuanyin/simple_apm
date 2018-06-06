require "simple_apm/setting"
require "simple_apm/redis"
require "simple_apm/engine"
require 'callsite'
module SimpleApm
  ActiveSupport::Notifications.subscribe('process_action.action_controller') do |name, started, finished, unique_id, payload|
    begin
      request_id = Thread.current['action_dispatch.request_id']
      need_skip = payload[:controller] == 'SimpleApm::ApmController'
      need_skip = true if payload[:status].to_s=='302' && payload[:path].to_s=~/login/ && payload[:method].to_s.downcase=='get'
      if request_id.present?
        if need_skip
          SimpleApm::Sql.delete_by_request_id(request_id)
        else
          action_name = "#{payload[:controller]}##{payload[:action]}" #payload[:format]
          info = {
              request_id: request_id,
              action_name: action_name,
              during: finished - started,
              started: started.to_s,
              db_runtime: payload[:db_runtime].to_f / 1000,
              view_runtime: payload[:view_runtime].to_f / 1000,
              controller: payload[:controller],
              action: payload[:action],
              host: Socket.gethostname,
              remote_addr: (payload[:headers]['HTTP_X_REAL_IP'] rescue nil),
              method: payload[:method],
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

  ActiveSupport::Notifications.subscribe 'sql.active_record' do |name, started, finished, unique_id, payload|
    begin
      request_id = Thread.current['action_dispatch.request_id'].presence || Thread.main['action_dispatch.request_id']
      if request_id.present?
        dev_caller = caller.detect {|c| c.include? Rails.root.to_s}
        if dev_caller
          c = ::Callsite.parse(dev_caller)
          payload.merge!(:line => c.line, :filename => c.filename.to_s.gsub(Rails.root.to_s, ''), :method => c.method)
        end
        # ActiveRecord::Relation::QueryAttribute
        sql_value = payload[:binds].map {|q| [q.name, q.value]} rescue nil
        info = {
            request_id: request_id,
            name: payload[:name],
            during: finished - started,
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
