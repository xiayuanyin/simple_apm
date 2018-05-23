# 慢请求列表,包括最慢的N个请求，指定Action的最慢的N个请求
module SimpleApm
  class SlowRequest
    attr_accessor :action_name, :request_id, :during
    def initialize(request_id, during, action_name = nil)
      self.action_name = action_name
      self.request_id = request_id
      self.during = during
    end


    def request
      @request_info ||= SimpleApm::Request.find(request_id)
    end

    def sqls
      @request_sqls ||= SimpleApm::Sql.all(request_id)
    end

    class << self
      # @param action_name [String] 请求名ControllerName#ActionName.Format
      # @param during [Float] 耗时
      # @param request_id [Hash] 请求id
      # @return [Boolean] 是否插入成功
      def append_by_action(action_name, during, request_id)
        _key = SimpleApm::RedisKey["action-slow:#{action_name}"]
        SimpleApm::Redis.zadd(_key, during, request_id)
        SimpleApm::Redis.zremrangebyrank(_key, 0, -SimpleApm::Setting::ACTION_SLOW_REQUEST_LIMIT - 1)
        SimpleApm::Redis.zrank(_key, request_id).present?
      end

      # @param request_id [Hash] 请求id
      # @param during [Float] 耗时
      # @return [Boolean] 是否插入成功
      def append(during, request_id)
        _key = SimpleApm::RedisKey['slow-requests']
        # 记录最慢请求列表1000个
        SimpleApm::Redis.zadd(_key, during, request_id)
        SimpleApm::Redis.zremrangebyrank(_key, 0, -SimpleApm::Setting::SLOW_ACTIONS_LIMIT - 1)
        SimpleApm::Redis.zrank(_key, request_id).present?
      end

      # 从慢到快的排序
      # @return [Array<SimpleApm::SlowRequest>]
      def list_by_action(action_name, limit = 100, offset = 0)
        _key = SimpleApm::RedisKey["action-slow:#{action_name}"]
        SimpleApm::Redis.zrevrange(
          _key, offset, limit, with_scores: true
        ).map{ |x| SimpleApm::SlowRequest.new(x[0], x[1], action_name)}
      end

      # 从慢到快的排序
      # @return [Array<SimpleApm::SlowRequest>]
      def list(limit = 100, offset = 0)
        _key = SimpleApm::RedisKey['slow-requests']
        SimpleApm::Redis.zrevrange(
          _key, offset, limit, with_scores: true
        ).map{ |x| SimpleApm::SlowRequest.new(x[0], x[1])}
      end
    end

  end
end
