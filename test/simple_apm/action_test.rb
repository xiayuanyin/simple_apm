require "test_helper"

module SimpleApm
  class ActionTest < ActiveSupport::TestCase
    test "update_by_request accumulates database runtime for action summaries" do
      calls = []
      incr_calls = []

      with_singleton_method(SimpleApm::Redis, :sadd, ->(*) {}) do
        with_singleton_method(SimpleApm::Redis, :hincrby, ->(*args) { incr_calls << args }) do
          with_singleton_method(SimpleApm::Redis, :hincrbyfloat, ->(*args) { calls << args }) do
            with_singleton_method(SimpleApm::Redis, :hget, ->(*) {}) do
              with_singleton_method(SimpleApm::Redis, :hmset, ->(*) {}) do
                SimpleApm::Action.update_by_request(
                  "action_name" => "ArticlesController#show",
                  "during" => 1.25,
                  "net_http_during" => 0.2,
                  "db_runtime" => 0.015,
                  "queries_count" => 7,
                  "cached_queries_count" => 2,
                  "request_id" => "request-1"
                )
              end
            end
          end
        end
      end

      assert_includes calls, [SimpleApm::Action.info_key("ArticlesController#show"), "db_time", 0.015]
      assert_includes incr_calls, [SimpleApm::Action.info_key("ArticlesController#show"), "queries_count", 7]
      assert_includes incr_calls, [SimpleApm::Action.info_key("ArticlesController#show"), "cached_queries_count", 2]
    end

    test "avg_db_time returns database runtime divided by click count" do
      action = SimpleApm::Action.new("db_time" => 0.03, "click_count" => 2)

      assert_in_delta 0.015, action.avg_db_time
    end

    test "avg_queries_count returns query count divided by click count" do
      action = SimpleApm::Action.new("queries_count" => 8, "click_count" => 2)

      assert_in_delta 4.0, action.avg_queries_count
    end

    test "averages stay finite for actions without recorded requests" do
      [nil, 0, "0"].each do |count|
        action = SimpleApm::Action.new(click_count: count, time: 1.0, db_time: 0.2,
          http_time: 0.1, queries_count: 3, cached_queries_count: 2)

        [:avg_time, :avg_db_time, :avg_http_time, :avg_queries_count, :avg_cached_queries_count].each do |metric|
          assert_equal 0.0, action.public_send(metric)
          assert action.public_send(metric).finite?
        end
      end
    end

    private

    def with_singleton_method(klass, method_name, replacement)
      singleton_class = class << klass; self; end
      had_method = singleton_class.method_defined?(method_name)
      original = klass.method(method_name) if had_method
      singleton_class.remove_method(method_name) if had_method
      singleton_class.define_method(method_name, replacement)
      yield
    ensure
      singleton_class.remove_method(method_name)
      singleton_class.define_method(method_name, original) if had_method
    end
  end
end
