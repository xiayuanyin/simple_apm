require 'test_helper'

class SimpleApm::Test < ActiveSupport::TestCase
  test "truth" do
    assert_kind_of Module, SimpleApm
  end

  test "dummy app uses Rails 8 defaults" do
    assert_equal "8.1", Rails.application.config.loaded_config_version.to_s
  end

  test "engine installs the APM rack middleware" do
    middleware = Rails.application.middleware.map(&:klass)

    assert_includes middleware, SimpleApm::Rack
  end

  test "RedisKey.set_query_date restores the previous query date after a block" do
    SimpleApm::RedisKey.query_date = "2026-06-01"

    yielded = SimpleApm::RedisKey.set_query_date("2026-06-02") do
      SimpleApm::RedisKey.query_date
    end

    assert_equal "2026-06-02", yielded
    assert_equal "2026-06-01", SimpleApm::RedisKey.query_date
  ensure
    SimpleApm::RedisKey.query_date = nil
  end

  test "merge_callsite_payload handles Ruby 3.4 caller location labels" do
    path = Rails.root.join("app/controllers/application_controller.rb").to_s
    location = Struct.new(:path, :lineno, :base_label).new(
      path,
      40,
      "ApplicationController#redirect_guest_with_locale"
    )
    payload = {}

    SimpleApm.merge_callsite_payload!(payload, [location])

    assert_equal 40, payload[:line]
    assert_equal "/app/controllers/application_controller.rb", payload[:filename]
    assert_equal "ApplicationController#redirect_guest_with_locale", payload[:method]
  end
end
