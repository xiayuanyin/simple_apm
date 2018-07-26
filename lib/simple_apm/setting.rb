module SimpleApm
  class Setting
    ApmSettings = YAML.load(IO.read("config/simple_apm.yml")) rescue {}
    REDIS_URL = ApmSettings['redis_url'].presence || 'redis://localhost:6379/0'
    # nil , hiredis ...
    REDIS_DRIVER = ApmSettings['redis_driver']
    # 最慢的请求数存储量
    SLOW_ACTIONS_LIMIT = ApmSettings['slow_actions_limit'].presence || 500
    # 每个action存最慢的请求量
    ACTION_SLOW_REQUEST_LIMIT = ApmSettings['action_slow_request_limit'].presence || 20
    # 区分项目显示
    APP_NAME = ApmSettings['app_name'].presence || 'app'
    # SQL临界值
    SQL_CRITICAL_TIME = ApmSettings['sql_critical_time'].to_f
    # 不纳入统计的action
    t = ApmSettings['exclude_actions']
    EXCLUDE_ACTIONS = t.is_a?(Array) ? t : [t]
  end
end
