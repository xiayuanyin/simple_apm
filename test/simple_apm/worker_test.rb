require "test_helper"

module SimpleApm
  class WorkerTest < ActiveSupport::TestCase
    test "stores controller events with Rails notification payload fields" do
      started = Time.now
      finished = started + 1.25
      event = {
        name: "process_action.action_controller",
        request_id: "request-1",
        remote_addr: "127.0.0.1",
        started: started,
        finished: finished,
        started_memory: 40.0,
        completed_memory: 41.5,
        net_http_during: 0.2,
        payload: {
          controller: "ArticlesController",
          action: "show",
          path: "/articles/1",
          db_runtime: 15.0,
          view_runtime: 5.0,
          queries_count: 7,
          cached_queries_count: 2,
          method: "GET",
          format: :html
        }
      }
      stored_requests = []

      with_class_method(SimpleApm::SlowRequest, :update_by_request, ->(_info) { true }) do
        with_class_method(SimpleApm::Action, :update_by_request, ->(_info) { false }) do
          with_class_method(SimpleApm::Hit, :update_by_request, ->(_info) { true }) do
            with_class_method(SimpleApm::Request, :create, ->(info) { stored_requests << info }) do
              SimpleApm::Worker.process!(event)
            end
          end
        end
      end

      assert_equal 1, stored_requests.length
      assert_equal "request-1", stored_requests.first[:request_id]
      assert_equal "ArticlesController#show", stored_requests.first[:action_name]
      assert_in_delta 1.25, stored_requests.first[:during]
      assert_in_delta 0.015, stored_requests.first[:db_runtime]
      assert_in_delta 0.005, stored_requests.first[:view_runtime]
      assert_equal 7, stored_requests.first[:queries_count]
      assert_equal 2, stored_requests.first[:cached_queries_count]
      assert_in_delta 1.5, stored_requests.first[:memory_during]
    end

    private

    def with_class_method(klass, method_name, replacement)
      singleton_class = class << klass; self; end
      original = klass.method(method_name)
      singleton_class.remove_method(method_name)
      singleton_class.define_method(method_name, replacement)
      yield
    ensure
      singleton_class.remove_method(method_name)
      singleton_class.define_method(method_name, original)
    end
  end
end
