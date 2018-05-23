# 删除
# redis-cli keys "jkb_rails:analyzer:*" | xargs redis-cli del
module SimpleApm
  class Query
    def initialize(t = Time.now)
      raise 'must be init by Time' unless t.is_a?(Time)
      @prefix = "apm:#{t.strftime('%Y-%m-%d')}:"
    end

    # 所有action
    def all_action_infos
      actions = SimpleApm::Redis.smembers get_key('action-names')
      actions.map! do |a|
        h = SimpleApm::Redis.hgetall(get_key("action-info:#{a}"))
        h.merge!(
          'name' => a,
          'avg_time' => (h['time'].to_f/h['click_count'].to_i).round(2)
        )
      end
    end



    # action最慢的100条记录
    def action_slow_requests(action_name)
      # [["da4f451a24a972e7e2af", 0.765782], ...]
      SimpleApm::Redis.zrevrange(get_key("action-slow:#{action_name}"), 0, -1, with_scores: true)
    end

    def all_slow_requests(limit = 100)
      SimpleApm::Redis.zrevrange(get_key('slow-requests'), 0, limit)
    end

    def get_action_info(action_name)
      h = SimpleApm::Redis.hgetall(get_key("action-info:#{action_name}"))
      h.merge!(
        'name' => action_name,
        'avg_time' => (h['time'].to_f/h['click_count'].to_i).round(2)
      )
    end

    def get_request_info(id)
      JSON.parse SimpleApm::Redis.hget(get_key('requests'), id)
    end

    def get_request_sqls(id)
      SimpleApm::Redis.lrange(get_key("sql:#{id}"), 0, -1).map{|x|JSON.parse(x)}
    end

    def get_key(name)
      "#{@prefix}#{name}"
    end
  end
end
