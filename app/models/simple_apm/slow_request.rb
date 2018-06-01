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
    alias :info :request

    def sqls
      @request_sqls ||= SimpleApm::Sql.find_by_request_id(request_id)
    end

    class << self
      # 存储最慢的1000个请求和每个action的最慢100次请求
      def update_by_request(info)
        in_action = update_action(info[:action_name], info[:during], info[:request_id])
        in_slow_request = update_request(info[:during], info[:request_id])
        in_action || in_slow_request
      end

      # @param action_name [String] 请求名ControllerName#ActionName
      # @param during [Float] 耗时
      # @param request_id [Hash] 请求id
      # @return [Boolean] 是否插入成功
      def update_action(action_name, during, request_id)
        SimpleApm::Redis.zadd(action_key(action_name), during, request_id)
        SimpleApm::Redis.zremrangebyrank(action_key(action_name), 0, -SimpleApm::Setting::ACTION_SLOW_REQUEST_LIMIT - 1)
        SimpleApm::Redis.zrank(action_key(action_name), request_id).present?
      end

      # @param request_id [Hash] 请求id
      # @param during [Float] 耗时
      # @return [Boolean] 是否插入成功
      def update_request(during, request_id)
        # 记录最慢请求列表1000个
        SimpleApm::Redis.zadd(key, during, request_id)
        SimpleApm::Redis.zremrangebyrank(key, 0, -SimpleApm::Setting::SLOW_ACTIONS_LIMIT - 1)
        SimpleApm::Redis.zrank(key, request_id).present?
      end

      # 从慢到快的排序
      # @return [Array<SimpleApm::SlowRequest>]
      def list_by_action(action_name, limit = 100, offset = 0)
        SimpleApm::Redis.zrevrange(
          action_key(action_name), offset, limit, with_scores: true
        ).map{ |x| SimpleApm::SlowRequest.new(x[0], x[1], action_name)}
      end

      # 从慢到快的排序
      # @return [Array<SimpleApm::SlowRequest>]
      def list(limit = 100, offset = 0)
        SimpleApm::Redis.zrevrange(
          key, offset.to_i, limit.to_i - 1, with_scores: true
        ).map{ |x| SimpleApm::SlowRequest.new(x[0], x[1])}
      end

      def key
        SimpleApm::RedisKey['slow-requests']
      end

      def action_key(action_name = nil)
        SimpleApm::RedisKey["action-slow:#{action_name}"]
      end

    end

  end
end
