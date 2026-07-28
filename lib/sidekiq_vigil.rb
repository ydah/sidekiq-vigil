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

    def build_storage(configuration = config)
      redis = if configuration.redis
                options = configuration.redis.transform_keys(&:to_sym).compact
                pool_size = options.delete(:pool_size) || 5
                pool_timeout = options.delete(:pool_timeout) || 1
                RedisClient.config(**options).new_pool(size: pool_size, timeout: pool_timeout)
              end
      Storage.new(redis:, key_prefix: configuration.key_prefix)
    end

    def install!
      return if @installed

      Sidekiq.configure_server do |server|
        server.server_middleware { |chain| chain.add(Middleware::Server) }
        server.on(:startup) { start_runtime }
        server.on(:quiet) { @runtime&.quiet }
        server.on(:shutdown) { stop_runtime }
      end
      @installed = true
    end

    def start_runtime
      @runtime ||= Runtime.new(config:, storage: build_storage)
      @runtime.start
    end

    def stop_runtime
      @runtime&.stop
      @runtime = nil
    end

    def reset!
      @config = Config.new
      @collector = Collector.new
      @logger = nil
      @runtime = nil
    end
  end
end

require_relative "sidekiq_vigil/result"
require_relative "sidekiq_vigil/config"
require_relative "sidekiq_vigil/storage"
require_relative "sidekiq_vigil/sidekiq_api"
require_relative "sidekiq_vigil/timezone"
require_relative "sidekiq_vigil/check/base"
require_relative "sidekiq_vigil/check/registry"
require_relative "sidekiq_vigil/check/queue_latency"
require_relative "sidekiq_vigil/check/queue_size"
require_relative "sidekiq_vigil/check/set_size"
require_relative "sidekiq_vigil/check/process_alive"
require_relative "sidekiq_vigil/check/utilization"
require_relative "sidekiq_vigil/check/failure_rate"
require_relative "sidekiq_vigil/check/stuck_jobs"
require_relative "sidekiq_vigil/check/memory"
require_relative "sidekiq_vigil/check/redis_health"
require_relative "sidekiq_vigil/check/scheduled_backlog"
require_relative "sidekiq_vigil/check/throughput_anomaly"
require_relative "sidekiq_vigil/alert/state"
require_relative "sidekiq_vigil/alert/event"
require_relative "sidekiq_vigil/alert/cron"
require_relative "sidekiq_vigil/alert/mute"
require_relative "sidekiq_vigil/alert/grouping"
require_relative "sidekiq_vigil/alert/manager"
require_relative "sidekiq_vigil/notifier/base"
require_relative "sidekiq_vigil/notifier/log"
require_relative "sidekiq_vigil/notifier/http_transport"
require_relative "sidekiq_vigil/notifier/webhook"
require_relative "sidekiq_vigil/notifier/slack"
require_relative "sidekiq_vigil/notifier/manager"
require_relative "sidekiq_vigil/leader_election"
require_relative "sidekiq_vigil/collector"
require_relative "sidekiq_vigil/middleware/server"
require_relative "sidekiq_vigil/reporter"
require_relative "sidekiq_vigil/checker"
require_relative "sidekiq_vigil/runtime"
require_relative "sidekiq_vigil/health_app"
require_relative "sidekiq_vigil/cli"

SidekiqVigil::BUILT_IN_CHECKS = {
  queue_latency: SidekiqVigil::Check::QueueLatency,
  queue_size: SidekiqVigil::Check::QueueSize,
  retry_set: SidekiqVigil::Check::RetrySet,
  dead_set: SidekiqVigil::Check::DeadSet,
  process_alive: SidekiqVigil::Check::ProcessAlive,
  utilization: SidekiqVigil::Check::Utilization,
  failure_rate: SidekiqVigil::Check::FailureRate,
  stuck_jobs: SidekiqVigil::Check::StuckJobs,
  memory: SidekiqVigil::Check::Memory,
  redis_health: SidekiqVigil::Check::RedisHealth,
  scheduled_backlog: SidekiqVigil::Check::ScheduledBacklog,
  throughput_anomaly: SidekiqVigil::Check::ThroughputAnomaly
}.freeze

SidekiqVigil.install!
