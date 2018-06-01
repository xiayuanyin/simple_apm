# 请求 Controller#Action
module SimpleApm
  class Action
    attr_accessor :name, :click_count, :time, :slow_time, :slow_id, :fast_time, :fast_id

    def initialize(h)
      h.each do |k, v|
        send("#{k}=", v)
      end
    end

    def fastest_request
      @fastest_request ||= SimpleApm::Request.find(fast_id)
    end
    def slowest_request
      @slowest_request ||= SimpleApm::Request.find(slow_id)
    end

    # @return [Array<SimpleApm::SlowRequest>]
    def slow_requests(limit = 20, offset = 0)
      @slow_requests ||= SimpleApm::SlowRequest.list_by_action(name, limit, offset)
    end

    def avg_time
      time.to_f/click_count.to_i
    end

    class << self
      def find(action_name)
        SimpleApm::Action.new SimpleApm::Redis.hgetall(info_key(action_name)).merge(name: action_name)
      end

      # @param h [Hash] 一次request请求的信息
      def update_by_request(h)
        SimpleApm::Redis.sadd(action_list_key, h['action_name'])
        _key = info_key h['action_name']
        _request_store = false
        # 点击次数
        SimpleApm::Redis.hincrby _key, 'click_count', 1
        # 总时间
        SimpleApm::Redis.hincrbyfloat _key, 'time', h['during']
        _slow = SimpleApm::Redis.hget _key, 'slow_time'
        if _slow.nil? || h['during'].to_f > _slow.to_f
          # 记录最慢访问
          SimpleApm::Redis.hmset _key, 'slow_time', h['during'], 'slow_id', h['request_id']
          _request_store = true
        end
        _fast = SimpleApm::Redis.hget _key, 'fast_time'
        if _fast.nil? || h['during'].to_f < _fast.to_f
          # 记录最快访问
          SimpleApm::Redis.hmset _key, 'fast_time', h['during'], 'fast_id', h['request_id']
          _request_store = true
        end
        _request_store
      end

      # @return [Array<String>]
      def all_names
        SimpleApm::Redis.smembers(action_list_key)
      end

      def action_list_key
        SimpleApm::RedisKey['action-names']
      end

      def info_key(action_name)
        SimpleApm::RedisKey["action-info:#{action_name}"]
      end
    end

  end
end
