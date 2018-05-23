# 请求对应的SQL查询列表
module SimpleApm
  class Sql
    attr_accessor :request_id, :sql
    def initialize(h)

    end

    class << self
      def all(request_id)
        _key = SimpleApm::Key["sql:#{request_id}"]
        SimpleApm::Redis.lrange(_key, 0, -1).map{|x|SimpleApm::Sql.new JSON.parse(x)}
      end
    end
  end
end
