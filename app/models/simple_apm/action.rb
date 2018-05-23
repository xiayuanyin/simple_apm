# 请求 Controller#Action
module SimpleApm
  class Action
    attr_accessor :name

    class << self
      def find

      end

      def create(h)
        SimpleApm::Redis.sadd(SimpleApm::RedisKey['action-names'], h['action_name'])
      end

      # @return [Array<String>]
      def all_names
        SimpleApm::Redis.smembers(SimpleApm::RedisKey['action-names'])
      end
    end

  end
end
