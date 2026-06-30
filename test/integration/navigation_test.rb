require 'test_helper'

class NavigationTest < ActionDispatch::IntegrationTest
  test "dashboard uses English by default" do
    with_dashboard_data do
      get "/simple_apm/dashboard"

      assert_response :success
      assert_select ".apm-page-title", "Performance Overview"
      assert_select ".apm-nav a", text: "Slow Requests"
      assert_select ".apm-language-switch a.active", text: "English"
    end
  end

  test "language switch changes dashboard to Chinese and persists in session" do
    with_dashboard_data do
      get "/simple_apm/set_locale", params: {locale: "zh-CN"}, headers: {"HTTP_REFERER" => "/simple_apm/dashboard"}
      follow_redirect!

      assert_response :success
      assert_select ".apm-page-title", "性能概览"
      assert_select ".apm-nav a", text: "慢事务列表"
      assert_select ".apm-language-switch a.active", text: "中文"

      get "/simple_apm/dashboard"

      assert_response :success
      assert_select ".apm-page-title", "性能概览"
    end
  end

  private

  def with_dashboard_data
    with_singleton_stub(SimpleApm::Redis, :in_apm_days, ["2026-06-30"]) do
      with_singleton_stub(SimpleApm::Redis, :running?, true) do
        with_singleton_stub(SimpleApm::Redis, :simple_info, {"redis" => "ok"}) do
          with_singleton_stub(SimpleApm::RedisKey, :query_date, "2026-06-30") do
            with_singleton_stub(SimpleApm::RedisKey, :query_date=, "2026-06-30") do
              with_singleton_stub(SimpleApm::Hit, :chart_data, {"00:00" => {hits: 1, time: 0.2}}) do
                yield
              end
            end
          end
        end
      end
    end
  end

  def with_singleton_stub(object, method_name, value)
    singleton_class = class << object; self; end
    original_method = object.method(method_name)

    singleton_class.define_method(method_name) { |*| value }
    yield
  ensure
    singleton_class.define_method(method_name, original_method)
  end
end
