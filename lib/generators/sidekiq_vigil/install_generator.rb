# frozen_string_literal: true

require "fileutils"

begin
  require "rails/generators"

  module SidekiqVigil
    module Generators
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        def copy_initializer
          template "sidekiq_vigil.rb", "config/initializers/sidekiq_vigil.rb"
        end
      end
    end
  end
rescue LoadError
  module SidekiqVigil
    module Generators
      class InstallGenerator
        TEMPLATE = File.expand_path("templates/sidekiq_vigil.rb", __dir__)

        def self.install(destination)
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.cp(TEMPLATE, destination)
        end
      end
    end
  end
end
