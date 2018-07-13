# 删除 所有
# redis-cli keys "simple_apm:*" | xargs redis-cli del
require 'redis-namespace'
module SimpleApm
  class Redis
    class << self
      def instance
        @current ||= ::Redis::Namespace.new(
          "simple_apm:#{SimpleApm::Setting::APP_NAME}",
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
          elsif k == 'used_memory_human'
            h['当前内存占用'] = v
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
        SimpleApm::Redis.keys('*:action-names').map{|x|x.split(':').first}.sort.reverse
      end

      # 清理指定日期之前的数据
      def clear_data_before_time(date)
        i = 0
        SimpleApm::Redis.in_apm_days.each do |d|
          SimpleApm::Redis.clear_data(d) and i+=1 if Time.parse(d) <= date
        end
        i
      end

      def clear_data(date_str)
        return {success: false, msg: '当日没有数据'} unless in_apm_days.include?(date_str)
        keys = SimpleApm::Redis.keys("#{date_str}:*")
        {success: true, msg: SimpleApm::Redis.del(keys)}
      end

      def running?
        hget('status','running').to_s != 'false'
      rescue
        false
      end

      def rerun!
        hset('status', 'running', true)
      end

      # 停止收集数据
      def stop!
        hset('status', 'running', false)
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
