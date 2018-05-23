# 单个请求信息
module SimpleApm
  class Request
    attr_accessor :id, :sqls
    def initialize(h)
      self.id = h[]
    end

    def sqls
      @sqls ||= SimpleApm::Sql.all(id)
    end

    def find(id)
      SimpleApm::Request.new JSON.parse(SimpleApm::Redis.hget(get_key('requests'), id))
    end
  end
end
