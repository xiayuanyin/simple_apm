require 'rails/generators'
module SimpleApm
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc "Create Notifications's base files"
      source_root File.expand_path('../../../../', __FILE__)

      def add_default_config
        path = "#{Rails.root}/config/simple_apm.yml"
        if File.exist?(path)
          puts 'Skipping config/simple_apm.yml creation, as file already exists!'
        else
          puts 'Adding simple_apm default config file (config/simple_apm.yml)...'
          template 'config/simple_apm.yml', path
        end
      end

      def add_routes
        route 'mount SimpleApm::Engine => "/apm"'
      end
    end
  end
end
