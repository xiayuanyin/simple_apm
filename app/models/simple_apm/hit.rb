# action的点击数，按小时来显示
module SimpleApm
  class Hit


    class << self
      def chart_data(start_time = '00:00', end_time = '23:50', per = 'minute')
        start_hour = start_time.to_s.split(':').first.to_i
        end_hour = [end_time.to_s.split(':').first.to_i, 23].min
        end_min = end_time.to_s.split(':')[1]
        minutes = %w[00 10 20 30 40 50]
        redis_result = Hash[SimpleApm::Redis.hgetall(minute_key)]
        result_hash = {}
        start_hour.upto(end_hour).each do |_hour|
          minutes.each do |_min|
            break if end_hour.to_i==_hour && end_min && _min.to_i > end_min.to_i
            k = "#{to_double_str _hour}:#{to_double_str _min}"
            _time = redis_result["#{k}:time"].to_f
            _hits = redis_result["#{k}:hits"].to_i
            if per =='minute'
              result_hash[k] = {time: _time, hits: _hits}
            else
              _key = to_double_str _hour
              result_hash[_key] ||= { time: 0.0, hits: 0 }
              result_hash[_key][:time] += _time
              result_hash[_key][:hits] += _hits
            end
          end
        end
        result_hash
      end


      def update_by_request(h)
        # SimpleApm::Redis.hincrby hour_hit_key, Time.now.hour, 1
        minute_base = "#{to_double_str Time.now.hour}:#{to_double_str 10 * (Time.now.min / 10)}"
        SimpleApm::Redis.hincrby minute_key, "#{minute_base}:hits", 1
        SimpleApm::Redis.hincrbyfloat minute_key, "#{minute_base}:time", h['during']
      end

      def to_double_str(i)
        i.to_s.size==1 ? "0#{i}" : i.to_s
      end

      def minute_key
        SimpleApm::RedisKey['per-10-minute']
      end

      # def hour_hit_key
      #   SimpleApm::RedisKey['hour-hits']
      # end
    end
  end
end
