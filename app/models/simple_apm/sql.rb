# 请求对应的SQL查询列表
module SimpleApm
  class Sql
    attr_accessor :request_id, :sql, :line, :filename, :method, :name, :during, :started, :value
    def initialize(h, request = nil)
      h.each do |k, v|
        send("#{k}=", v)  rescue puts "attr #{k} not set!"
      end
      @request = request
    end

    def full_sql
      _sql = sql.to_s.gsub(/^[\s]*/,'')
      if value.present?
        _sql << "\n\nParameters: #{value}"
      end
      _sql
    end

    def request
      @request ||= SimpleApm::Request.find(request_id)
    end

    class << self
      # @return [Array<SimpleApm::Sql>]
      def find_by_request_id(request_id)
        SimpleApm::Redis.lrange(key(request_id), 0, -1).map{|x|SimpleApm::Sql.new JSON.parse(x)}
      end

      def delete_by_request_id(request_id)
        SimpleApm::Redis.del(key(request_id))
      end

      def create(request_id, info)
        SimpleApm::Redis.rpush(key(request_id), info.to_json)
      end

      def key(request_id)
        SimpleApm::RedisKey["sql:#{request_id}"]
      end
    end
  end
end
