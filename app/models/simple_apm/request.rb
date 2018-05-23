# 单个请求信息
module SimpleApm
  class Request
    attr_accessor :id,
                  :during, :started, :db_runtime, :view_runtime,
                  :controller, :action, :format, :method,
                  :host, :remote_addr,
                  :exception
    def initialize(h)
      h.each do |k, v|
        send("#{k}=", v)
      end
    end

    def sqls
      @sqls ||= SimpleApm::Sql.all(id)
    end

    def find(id)
      SimpleApm::Request.new JSON.parse(SimpleApm::Redis.hget(SimpleApm::Request.key, id))
    end

    class << self
      def create(h)
        SimpleApm::Redis.hmset key, h['id'], h.to_json
      end

      def key
        SimpleApm::RedisKey['requests']
      end
    end
  end
end
