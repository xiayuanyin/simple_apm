require "test_helper"
require "tempfile"

module SimpleApm
  class SettingTest < ActiveSupport::TestCase
    test "load_settings evaluates ERB so simple_apm.yml can read ENV" do
      ENV["SIMPLE_APM_REDIS_URL"] = "redis://redis.example.test:6379/2"
      ENV["SIMPLE_APM_APP_NAME"] = "env-app"
      file = Tempfile.new("simple_apm.yml")
      file.write <<~YAML
        redis_url: <%= ENV.fetch("SIMPLE_APM_REDIS_URL") %>
        app_name: <%= ENV.fetch("SIMPLE_APM_APP_NAME") %>
        exclude_actions:
          - <%= ENV.fetch("SIMPLE_APM_EXCLUDE_ACTION", "OrdersController#create") %>
      YAML
      file.close

      settings = SimpleApm::Setting.load_settings(file.path)

      assert_equal "redis://redis.example.test:6379/2", settings["redis_url"]
      assert_equal "env-app", settings["app_name"]
      assert_equal ["OrdersController#create"], settings["exclude_actions"]
    ensure
      ENV.delete("SIMPLE_APM_REDIS_URL")
      ENV.delete("SIMPLE_APM_APP_NAME")
      file&.unlink
    end
  end
end
