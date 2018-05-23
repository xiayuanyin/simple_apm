module SimpleApm
  class Redis
    class << self
      def instance
        @current ||= ::Redis::Namespace.new(
          :simple_apm,
          :redis => ::Redis.new(
            url: SimpleApm::Setting::REDIS_URL,
            driver: SimpleApm::Setting::REDIS_DRIVER
          )
        )
      end

      def method_missing(method, *args)
        instance.send(method, *args)
      rescue NoMethodError
        super(method, *args)
      end
    end
  end

  class RedisKey
    class << self
      def query_date=(d = nil)
        Thread.current['apm_query_date'] = d
      end
      def query_date
        @date ||= (Thread.current['apm_query_date']||Time.now.strftime('%Y-%m-%d'))
      end

      def [](key)
        "#{self.query_date}:#{key}"
      end
    end
  end
end
