# 删除 所有
# redis-cli keys "simple_apm:*" | xargs redis-cli del
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

      # http://redisdoc.com/server/info.html
      def simple_info
        h = {}
        redis.info.each do |k, v|
          if k == 'total_system_memory_human'
            h['系统内存'] = v
          elsif k == 'used_memory_rss_human'
            h['当前内存占用(rss)'] = v
          elsif k == 'used_memory_peak_human'
            h['占用内存峰值'] = v
          elsif k == 'redis_version'
            h['redis版本'] = v
          elsif k =~ /db[0-9]+/
            h[k] = v
          end
        end
        h
      end

      # 所有统计的日期，通过hits来判断
      def in_apm_days
        SimpleApm::Redis.keys('*:action-names').map{|x|x.split(':').first}.sort
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
        Thread.current['apm_query_date'] || Time.now.strftime('%Y-%m-%d')
      end

      def [](key, _date = nil)
        "#{_date||query_date}:#{key}"
      end
    end
  end
end
