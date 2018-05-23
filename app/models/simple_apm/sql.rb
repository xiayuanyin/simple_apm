# 请求对应的SQL查询列表
module SimpleApm
  class Sql
    attr_accessor :request_id, :sql
    def initialize(h)

    end

    class << self
      # @return [Array<SimpleApm::Sql>]
      def all(request_id)
        SimpleApm::Redis.lrange(key(request_id), 0, -1).map{|x|SimpleApm::Sql.new JSON.parse(x)}
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
