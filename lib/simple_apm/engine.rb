module SimpleApm
  class Rack
    def initialize(app)
      @app = app
    end

    def call(env)
      if SimpleApm::Redis.running?
        Thread.current['action_dispatch.request_id'] = env['action_dispatch.request_id']
      end
      @app.call(env)
    end
  end

  class Engine < ::Rails::Engine
    isolate_namespace SimpleApm
    config.app_middleware.use SimpleApm::Rack
  end

end
