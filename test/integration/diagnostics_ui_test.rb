require 'test_helper'

class DiagnosticsUiTest < ActionDispatch::IntegrationTest
  DATE = '2026-10-12'.freeze

  test 'request detail renders a complete safe report and preserves date and locale navigation' do
    request_record = build_request
    sqls = [build_sql('SELECT </textarea><script data-diagnostic>throw 1</script>'), build_sql('SELECT COUNT(*) FROM orders')]
    http_call = SimpleApm::HttpRequest.new(name: 'GET', url: 'https://api.example.test/orders',
      path: '/orders', host: 'api.example.test', during: 0.4, filename: '/app/services/orders.rb', line: 12)

    with_ui_data(request_record: request_record, sqls: sqls, http_calls: [http_call]) do
      get '/simple_apm/set_locale', params: {locale: 'zh-CN'}
      get '/simple_apm/show', params: {id: request_record.request_id, apm_date: DATE}

      assert_response :success
      assert_select 'html[lang="zh-CN"]'
      assert_select '.apm-language-switch a.active', '中文'
      assert_select '.apm-breadcrumb a[href=?]', "/simple_apm/index?apm_date=#{DATE}", text: '返回慢请求列表'
      assert_select '.apm-breadcrumb a[href*="action_info"][href*=?]', "apm_date=#{DATE}", text: request_record.action_name
      assert_select '.apm-nav a[href=?]', "/simple_apm/actions?apm_date=#{DATE}"
      assert_select '.apm-date-form[action="/simple_apm/action_info"] input[name="action_name"][value="OrdersController#show"]'
      assert_select '#apm_date option[selected][value=?]', DATE
      report = diagnostic_report
      assert_equal 'request', report['type']
      assert_equal DATE, report['query_date']
      assert_equal request_record.request_id, report.dig('request', 'request_id')
      assert_equal 200, report.dig('request', 'status')
      assert_equal 1.5, report.dig('timings', 'total_seconds')
      assert_equal 2, report['sql'].length
      assert_equal sqls.first.sql, report['sql'].first['statement']
      assert_equal 1, report['http_calls'].length
      assert_select 'script[data-diagnostic]', count: 0
      assert_includes response.body, '&lt;/textarea&gt;&lt;script data-diagnostic&gt;'
    end
  end

  test 'action detail report includes metrics and retained requests with back navigation' do
    action = build_action
    request_record = build_request
    sample = SimpleApm::SlowRequest.new(request_record.request_id, request_record.during, action.name)

    with_ui_data(action: action, request_record: request_record, samples: [sample], sqls: [build_sql('SELECT 1')]) do
      get '/simple_apm/action_info', params: {action_name: action.name, apm_date: DATE}

      assert_response :success
      assert_select '.apm-breadcrumb a[href=?]', "/simple_apm/actions?apm_date=#{DATE}", text: 'Back to actions'
      assert_select 'a[href*="/simple_apm/show"][href*=?]', "apm_date=#{DATE}", count: 4
      assert_select '.apm-date-form input[name="action_name"][value="OrdersController#show"]'
      report = diagnostic_report
      assert_equal 'action', report['type']
      assert_equal DATE, report['query_date']
      assert_equal action.name, report['action_name']
      assert_equal 3, report.dig('metrics', 'requests')
      assert_equal 1.5, report.dig('metrics', 'averages', 'total_seconds')
      assert_equal true, report.dig('samples', 'slowest', 'available')
      assert_equal 1, report.dig('samples', 'retained_slow').length
      assert_equal 'SELECT 1', report.dig('samples', 'retained_slow', 0, 'report', 'sql', 0, 'statement')

      get "/simple_apm/actions?apm_date=#{DATE}"

      assert_response :success
      assert_select '#apm_date option[selected][value=?]', DATE
    end
  end

  test 'missing request and action details return a useful not found page' do
    with_ui_data do
      get '/simple_apm/show', params: {id: 'missing', apm_date: DATE}

      assert_response :not_found
      assert_select '.apm-page-title', 'Record unavailable'
      assert_select '#diagnostic-report', count: 0

      get '/simple_apm/action_info', params: {action_name: 'MissingController#show'}

      assert_response :not_found
      assert_select '.apm-page-title', 'Record unavailable'
      assert_select 'a[href="/simple_apm/actions"]'
    end
  end

  test 'slow request JSON escapes stored labels skips expired records and clamps requested sample counts' do
    request_record = build_request
    request_record.action_name = '<img src=x onerror=alert(1)>#show'
    request_record.during = 0.000123456
    request_record.host = '<script>host</script>'
    request_record.remote_addr = '<svg onload=alert(1)>'
    samples = [SimpleApm::SlowRequest.new(request_record.request_id, 1.5), SimpleApm::SlowRequest.new('expired', 1.0)]
    requested_counts = []

    with_ui_data(request_record: request_record, extra: [
      [SimpleApm::SlowRequest, :list, ->(count) { requested_counts << count; samples }]
    ]) do
      [{count: 999_999}, {count: -5}, {}].each do |params|
        get '/simple_apm/index.json', params: params.merge(apm_date: DATE)

        assert_response :success
        rows = JSON.parse(response.body)['data']
        assert_equal 1, rows.length
        [0, 1].each do |column|
          assert_includes Nokogiri::HTML.fragment(rows.first[column]).at_css('a')['href'], "apm_date=#{DATE}"
        end
        assert_includes rows.first[1], '&lt;img'
        duration = Nokogiri::HTML.fragment(rows.first[2]).at_css('span[data-seconds]')
        assert_equal request_record.during, duration['data-seconds'].to_f
        assert_equal '0 ms', duration.text
        assert_equal '&lt;script&gt;host&lt;/script&gt;', rows.first[8]
        assert_equal '&lt;svg onload=alert(1)&gt;', rows.first[9]
        rows.first.grep(String).each do |cell|
          assert_empty Nokogiri::HTML.fragment(cell).css('img, script, svg')
        end
      end
      assert_equal [SimpleApm::Setting::SLOW_ACTIONS_LIMIT.to_i, 1, 200], requested_counts
    end
  end

  test 'data controls use POST and GET cannot delete or pause collection' do
    mutations = []
    day = {day: DATE, hits: 3, time: 4.5, avg_time: 1.5}

    with_ui_data(extra: [
      [SimpleApm::Hit, :day_info, ->(*) { day }],
      [SimpleApm::Redis, :clear_data, ->(date) { mutations << [:delete, date]; {success: true} }],
      [SimpleApm::Redis, :stop!, -> { mutations << :stop }]
    ]) do
      get '/simple_apm/data'

      assert_response :success
      assert_select 'form[action*="data_delete"]', count: 4 do |forms|
        forms.each { |form| assert_equal 'post', form['method'] }
      end
      assert_select 'a[href*="data_delete"]', count: 0
      assert_raises(ActionController::RoutingError) do
        get '/simple_apm/data_delete', params: {date: DATE}
      end
      assert_raises(ActionController::RoutingError) do
        get '/simple_apm/data_delete', params: {type: 'stop_data'}
      end
      assert_empty mutations

      post '/simple_apm/data_delete', params: {date: DATE}
      assert_redirected_to '/simple_apm/data'
      assert_equal [[:delete, DATE]], mutations
    end
  end

  test 'dashboard displays request weighted average across intervals' do
    points = {'00:00' => {hits: 1, time: 1.0}, '00:10' => {hits: 9, time: 27.0}}

    with_ui_data(extra: [[SimpleApm::Hit, :chart_data, ->(*) { points }]]) do
      get '/simple_apm/dashboard', params: {apm_date: DATE}

      assert_response :success
      assert_select '.apm-stat:first-child .apm-stat-value', '2.8 s'
      assert_select '.apm-stat:nth-child(2) .apm-stat-value', '10'
    end
  end

  private

  def diagnostic_report
    assert_select 'button[data-copy-target="diagnostic-report"]', count: 1
    assert_select 'textarea#diagnostic-report[readonly]', count: 1
    JSON.parse(css_select('#diagnostic-report').first.text)
  end

  def build_request
    SimpleApm::Request.new(request_id: 'request-1', action_name: 'OrdersController#show',
      controller: 'OrdersController', action: 'show', method: 'GET', format: 'html', url: '/orders/42',
      host: 'worker-1', remote_addr: '127.0.0.1', status: 200, started: "#{DATE} 01:02:03 UTC",
      during: 1.5, db_runtime: 0.2, view_runtime: 0.3, net_http_during: 0.4, queries_count: 4,
      cached_queries_count: 2, completed_memory: 42.5, memory_during: 1.25, exception: 'null')
  end

  def build_action
    SimpleApm::Action.new(name: 'OrdersController#show', click_count: 3, time: 4.5, db_time: 0.6,
      http_time: 1.2, queries_count: 12, cached_queries_count: 6, fast_id: 'request-1',
      fast_time: 1.5, slow_id: 'request-1', slow_time: 1.5)
  end

  def build_sql(statement)
    SimpleApm::Sql.new(sql: statement, name: 'Order Load', during: 0.1, started: "#{DATE} 01:02:03 UTC",
      filename: '/app/models/order.rb', line: 8, method: 'find_order', cached: true)
  end

  def with_ui_data(action: nil, request_record: nil, samples: [], sqls: [], http_calls: [], extra: [], &block)
    previous_date = Thread.current['apm_query_date']
    stubs = [
      [SimpleApm::Redis, :in_apm_days, -> { [DATE] }],
      [SimpleApm::Redis, :running?, -> { true }],
      [SimpleApm::Redis, :simple_info, -> { {'redis' => 'ok'} }],
      [SimpleApm::Action, :find, ->(name) { action || SimpleApm::Action.new(name: name) }],
      [SimpleApm::Action, :all_names, -> { action ? [action.name] : [] }],
      [SimpleApm::Request, :find, ->(id) { request_record if request_record && id == request_record.request_id }],
      [SimpleApm::SlowRequest, :list_by_action, ->(*) { samples }],
      [SimpleApm::Sql, :find_by_request_id, ->(*) { sqls }],
      [SimpleApm::HttpRequest, :find_by_request_id, ->(*) { http_calls }]
    ]
    with_singleton_stubs(stubs + extra, &block)
  ensure
    Thread.current['apm_query_date'] = previous_date
  end

  def with_singleton_stubs(stubs, &block)
    return yield if stubs.empty?

    object, name, replacement = stubs.first
    original = object.method(name)
    object.define_singleton_method(name, replacement)
    with_singleton_stubs(stubs.drop(1), &block)
  ensure
    object.define_singleton_method(name, original) if original
  end
end
