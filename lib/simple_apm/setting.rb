module SimpleApm
  class Setting
    REDIS_URL = 'redis://localhost:6379/0'
    REDIS_DRIVER = :hiredis
    # 最慢的请求数存储量
    SLOW_ACTIONS_LIMIT = 1000
    # 每个action存最慢的请求量
    ACTION_SLOW_REQUEST_LIMIT = 100
  end
end
