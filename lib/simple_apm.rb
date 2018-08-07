require 'simple_apm/setting'
require 'simple_apm/redis'
require 'simple_apm/engine'
require 'simple_apm/worker'
require 'simple_apm/net_http'
require 'callsite'
require 'get_process_mem'
module SimpleApm

  SimpleApm::NetHttp.install

  ActiveSupport::Notifications.subscribe('process_action.action_controller') do |name, started, finished, unique_id, payload|
    ProcessingThread.add_event(
        name: name,
        request_id: Thread.current['action_dispatch.request_id'],
        started: started, finished: finished,
        payload: payload.reject{|k,v|k.to_s=='headers'},
        started_memory: Thread.current[:current_process_memory],
        completed_memory: GetProcessMem.new.mb,
        net_http_during: Thread.current[:net_http_during]
    )
    Thread.current['action_dispatch.request_id'] = nil
    Thread.current[:net_http_during] = nil
  end

  ActiveSupport::Notifications.subscribe 'net_http.request' do |name, started, finished, unique_id, payload|
    th = Thread.current['action_dispatch.request_id'].present? ? Thread.current : Thread.main
    request_id = th['action_dispatch.request_id']
    if request_id
      during = finished - started
      th[:net_http_during] += during if th[:net_http_during]
      if dev_caller = caller.detect {|c| c.include?(Rails.root.to_s) && !c.include?('/vendor/')}
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
              ::SimpleApm::Worker.process! e
            end
            sleep 0.5
          end
        end
      end
    end
  end

end
