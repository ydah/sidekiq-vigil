# frozen_string_literal: true

require "logger"
require "sidekiq"
require "sidekiq/api"

require_relative "sidekiq_vigil/version"

module SidekiqVigil
  class Error < StandardError; end

  class << self
    attr_writer :logger

    def configure
      yield config
      config.validate!
      config
    end

    def config
      @config ||= Config.new
    end

    def collector
      @collector ||= Collector.new
    end

    def logger
      @logger ||= defined?(Sidekiq.logger) ? Sidekiq.logger : Logger.new($stdout)
    end

    def reset!
      @config = Config.new
      @collector = Collector.new
      @logger = nil
    end
  end
end

require_relative "sidekiq_vigil/result"
require_relative "sidekiq_vigil/config"
require_relative "sidekiq_vigil/storage"
require_relative "sidekiq_vigil/check/base"
require_relative "sidekiq_vigil/check/registry"
require_relative "sidekiq_vigil/leader_election"
require_relative "sidekiq_vigil/collector"
require_relative "sidekiq_vigil/middleware/server"
require_relative "sidekiq_vigil/reporter"
