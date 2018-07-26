module SimpleApm
  class Rack
    def initialize(app)
      @app = app
    end

    def call(env)
      if SimpleApm::Redis.ping && SimpleApm::Redis.running?
        SimpleApm::ProcessingThread.start!
        Thread.current['action_dispatch.request_id'] = env['action_dispatch.request_id']
        Thread.current[:current_process_memory] = GetProcessMem.new.mb
      end
      @app.call(env)
    end
  end

  class Engine < ::Rails::Engine
    isolate_namespace SimpleApm
    config.app_middleware.use SimpleApm::Rack
  end

end
