module SimpleApm
  class Summary
    @@results = {}

    def initialize(date)
      @date = date
    end

    def result
      return @@results[@date] if @@results[@date] && Time.parse(@date) < Date.today
      @@results[@date] = SimpleApm::RedisKey.set_query_date(@date) do
        res = SimpleApm::Hit.day_info(@date)
        actions = SimpleApm::Action.all_names.map{|n|SimpleApm::Action.find(n)}
        most_hits_5 = actions.sort_by{|x|x.click_count.to_i}.reverse.take(5)
        most_hits_5.map! do |action|
          {
              name: action.name,
              avg_time: action.avg_time,
              hits: action.click_count.to_i,
              slow_avg_time: action.slow_requests.sum(&:during)/action.slow_requests.length
          }
        end
        {
            hits: res[:hits],
            avg_time: res[:avg_time],
            actions: most_hits_5
        }
      end

    end
  end
end
