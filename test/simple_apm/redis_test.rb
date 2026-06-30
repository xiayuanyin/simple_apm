require "test_helper"

module SimpleApm
  class RedisTest < ActiveSupport::TestCase
    test "stop writes string false for redis client compatibility" do
      calls = []

      with_singleton_method(SimpleApm::Redis, :hset, ->(*args) { calls << args }) do
        SimpleApm::Redis.stop!
      end

      assert_equal [["status", "running", "false"]], calls
    end

    test "rerun writes string true for redis client compatibility" do
      calls = []

      with_singleton_method(SimpleApm::Redis, :hset, ->(*args) { calls << args }) do
        SimpleApm::Redis.rerun!
      end

      assert_equal [["status", "running", "true"]], calls
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
