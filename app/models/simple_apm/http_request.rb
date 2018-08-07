# 请求对应的SQL查询列表
module SimpleApm
  class HttpRequest
    attr_accessor :request_id, :url, :line, :filename, :during, :started, :path, :host, :name
    def initialize(h, request = nil)
      h.each do |k, v|
        send("#{k}=", v)  rescue puts "attr #{k} not set!"
      end
      @request = request
    end

    def request
      @request ||= SimpleApm::Request.find(request_id)
    end

    class << self
      # @return [Array<SimpleApm::HttpRequest>]
      def find_by_request_id(request_id)
        SimpleApm::Redis.lrange(key(request_id), 0, -1).map{|x|SimpleApm::HttpRequest.new JSON.parse(x)}
      end

      def delete_by_request_id(request_id)
        SimpleApm::Redis.del(key(request_id))
      end

      def create(request_id, info)
        SimpleApm::Redis.rpush(key(request_id), info.to_json)
      end

      def key(request_id)
        SimpleApm::RedisKey["http_request:#{request_id}"]
      end
    end
  end
end
