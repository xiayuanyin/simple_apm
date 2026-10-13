require 'test_helper'

module SimpleApm
  class DiagnosticReportTest < ActiveSupport::TestCase
    test 'request report preserves measured units and all stored diagnostic records' do
      request = build_request
      sqls = [build_sql('SELECT * FROM orders WHERE id = 42'), build_sql('SELECT COUNT(*) FROM orders')]
      sqls.first.define_singleton_method(:cached) { true }
      call = HttpRequest.new(url: 'https://api.example.test/orders?page=2', path: '/orders?page=2', host: 'api.example.test',
        name: 'GET', during: 0.4, started: '2026-10-13 01:02:03 UTC', filename: '/app/services/orders.rb', line: 12)

      with_records(sqls: sqls, http_calls: [call]) do
        report = DiagnosticReport.for_request(request, date: '2026-10-13')

        assert_equal '1.0', report[:schema_version]
        assert_equal 'request', report[:type]
        assert_equal Setting::APP_NAME, report[:application]
        assert_equal '2026-10-13', report[:query_date]
        assert_match(/Z\z/, report[:generated_at])
        assert_equal({ duration: 'seconds', memory: 'MB', memory_bytes_per_mb: 1_048_576 }, report[:units])
        assert_equal 1.5, report[:timings][:total_seconds]
        assert_equal 0.2, report[:timings][:database_seconds]
        assert_equal 42.5, report[:memory][:completed_mb]
        assert_equal(-1.25, report[:memory][:change_mb])
        assert_equal 200, report[:request][:status]
        assert_equal 2, report[:sql].length
        assert_equal true, report[:sql].first[:cached]
        assert_equal 0.1, report[:sql].first[:duration_seconds]
        assert_equal({ filename: '/app/models/order.rb', line: 8, method: 'find_order' }, report[:sql].first[:location])
        assert_equal 42, report[:sql].first[:binds].first.last
        assert_equal 1, report[:http_calls].length
        assert_equal 0.4, report[:http_calls].first[:duration_seconds]
        assert_equal '/orders?page=2', report[:http_calls].first[:path]
        assert_equal Setting::SQL_CRITICAL_TIME.to_f, report[:sql_storage_threshold_seconds]
        assert report.to_json
      end
    end

    test 'credentials are filtered in urls binds sql and exceptions without changing stored data' do
      request = build_request
      request.url = 'https://alice:url-password@example.test/orders?token=url-token&page=2&account[pin]=custom-pin'
      request.exception = ['RuntimeError', 'password=exception-password Authorization: Bearer bearer-secret postgres://db-user:db-password@db.test/orders failed order=42'].to_json
      binds = [['id', 42], ['password', 'bind-password'], ['one_time_pin', 'bind-pin'], ['metadata', { 'session_id' => 'session-secret', 'page' => 2 }]]
      sql = build_sql(%q{SELECT * FROM orders WHERE "password" = 'inline-password' AND account_id = 42 AND token = 123456})
      sql.value = binds
      http = HttpRequest.new(url: 'https://bob:http-password@api.example.test/check?api_key=http-token&page=2',
        path: '/check?password=path-password&page=2')
      original = Marshal.dump([request.url, request.exception, sql.sql, binds, http.url, http.path])
      original_filters = Rails.application.config.filter_parameters
      Rails.application.config.filter_parameters = original_filters + [:one_time_pin, 'account.pin']

      with_records(sqls: [sql], http_calls: [http]) do
        report = DiagnosticReport.for_request(request, date: '2026-10-13')
        json = report.to_json

        %w[alice url-password url-token custom-pin exception-password bearer-secret db-user db-password bind-password bind-pin session-secret inline-password 123456 bob http-password http-token path-password].each do |secret|
          refute_includes json, secret
        end
        assert_includes report[:request][:url], 'page=2'
        assert_includes report[:sql].first[:statement], 'SELECT * FROM orders'
        assert_includes report[:sql].first[:statement], 'account_id = 42'
        assert_equal 42, report[:sql].first[:binds].first.last
        assert_equal '[FILTERED]', report[:sql].first[:binds][1].last
        assert_equal 2, report[:sql].first[:binds][3].last['page']
      end

      assert_equal original, Marshal.dump([request.url, request.exception, sql.sql, binds, http.url, http.path])
    ensure
      Rails.application.config.filter_parameters = original_filters
    end

    test 'SQL literals including inserts and dollar quoting are filtered while keeping structure' do
      sqls = [build_sql("INSERT INTO accounts (email, password) VALUES ('hello@example.test', 'insert-secret')"),
        build_sql('SELECT $$dollar-secret$$, $body$tagged-secret$body$ FROM accounts WHERE id = 5')]

      with_records(sqls: sqls) do
        report = DiagnosticReport.for_request(build_request, date: '2026-10-13')

        refute_includes report.to_json, 'insert-secret'
        refute_includes report.to_json, 'dollar-secret'
        refute_includes report.to_json, 'tagged-secret'
        assert_includes report[:sql].first[:statement], 'INSERT INTO accounts (email, password) VALUES'
        assert_includes report[:sql].last[:statement], 'FROM accounts WHERE id = 5'
      end
    end

    test 'action report includes aggregate totals averages and every retained slow sample' do
      request = build_request
      action = Action.new(name: 'OrdersController#show', click_count: '3', time: '4.5', db_time: '0.6', http_time: '1.2',
        queries_count: '12', cached_queries_count: '6', fast_id: 'missing-fast', fast_time: '0.5', slow_id: 'request-1', slow_time: '1.5')
      queried_limit = nil
      samples = [SlowRequest.new('request-1', 1.5), SlowRequest.new('missing-slow', 1.4)]

      with_records(requests: { 'request-1' => request }, sqls: [build_sql('SELECT 1')]) do
        with_singleton_method(SlowRequest, :list_by_action, ->(name, limit) { queried_limit = [name, limit]; samples }) do
          report = DiagnosticReport.for_action(action, date: '2026-10-13')

          assert_equal 'action', report[:type]
          assert_equal 3, report[:metrics][:requests]
          assert_equal 4.5, report[:metrics][:totals][:total_seconds]
          assert_equal 1.5, report[:metrics][:averages][:total_seconds]
          assert_in_delta 0.2, report[:metrics][:averages][:database_seconds]
          assert_equal 4.0, report[:metrics][:averages][:queries]
          assert_equal [action.name, Setting::ACTION_SLOW_REQUEST_LIMIT.to_i], queried_limit
          assert_equal false, report[:samples][:fastest][:available]
          assert_nil report[:samples][:fastest][:report]
          assert_equal true, report[:samples][:slowest][:available]
          assert_equal 1, report[:samples][:slowest][:report][:sql].length
          assert_equal 2, report[:samples][:retained_slow].length
          assert_equal false, report[:samples][:retained_slow].last[:available]
          assert_match(/not representative/, report[:limitations].first)
        end
      end
    end

    test 'missing action fields produce finite zero averages and unavailable samples' do
      with_records do
        with_singleton_method(SlowRequest, :list_by_action, ->(*) { [] }) do
          report = DiagnosticReport.for_action(Action.new(name: 'MissingController#show'), date: '2026-10-13')

          assert_equal 0, report[:metrics][:requests]
          assert report[:metrics][:averages].values.all? { |value| value.zero? && value.finite? }
          assert_nil report[:samples][:fastest][:request_id]
          assert_equal false, report[:samples][:slowest][:available]
          assert_equal [], report[:samples][:retained_slow]
          assert report.to_json
        end
      end
    end

    test 'legacy missing status cache and memory remain explicitly unavailable' do
      request = Request.new(request_id: 'legacy', during: 0.1, exception: 'null')

      with_records(sqls: [build_sql('SELECT 1')]) do
        report = DiagnosticReport.for_request(request, date: '2026-10-13')

        assert_nil report[:request][:status]
        assert_nil report[:request][:exception]
        assert_nil report[:sql].first[:cached]
        assert_nil report[:memory][:completed_mb]
        assert_nil report[:counters][:cached_queries]
      end
    end

    test 'reports scope lookups to the requested date and restore the previous date even on failure' do
      previous_date = Thread.current['apm_query_date']
      Thread.current['apm_query_date'] = '2026-10-12'
      lookup_date = nil
      with_singleton_method(Sql, :find_by_request_id, ->(*) { lookup_date = RedisKey.query_date; raise 'lookup failed' }) do
        assert_raises(RuntimeError) { DiagnosticReport.for_request(build_request, date: '2026-10-13') }
      end
      assert_equal '2026-10-13', lookup_date
      assert_equal '2026-10-12', RedisKey.query_date
    ensure
      Thread.current['apm_query_date'] = previous_date
    end

    private

    def build_request
      Request.new(request_id: 'request-1', action_name: 'OrdersController#show', controller: 'OrdersController', action: 'show',
        method: 'GET', format: 'html', url: '/orders/42', host: 'worker-1', remote_addr: '127.0.0.1', status: 200,
        started: '2026-10-13 01:02:03 UTC', during: 1.5, db_runtime: 0.2, view_runtime: 0.3, net_http_during: 0.4,
        queries_count: 4, cached_queries_count: 2, completed_memory: 42.5, memory_during: -1.25, exception: 'null')
    end

    def build_sql(statement)
      Sql.new(sql: statement, name: 'Order Load', value: [['id', 42]], during: 0.1,
        started: '2026-10-13 01:02:03 UTC', filename: '/app/models/order.rb', line: 8, method: 'find_order')
    end

    def with_records(requests: {}, sqls: [], http_calls: [])
      with_singleton_method(Request, :find, ->(id) { requests[id] }) do
        with_singleton_method(Sql, :find_by_request_id, ->(*) { sqls }) do
          with_singleton_method(HttpRequest, :find_by_request_id, ->(*) { http_calls }) { yield }
        end
      end
    end

    def with_singleton_method(object, name, replacement)
      original = object.method(name)
      object.define_singleton_method(name, replacement)
      yield
    ensure
      object.define_singleton_method(name, original)
    end
  end
end
