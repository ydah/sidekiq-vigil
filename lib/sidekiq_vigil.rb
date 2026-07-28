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
require_relative "sidekiq_vigil/leader_election"
require_relative "sidekiq_vigil/collector"
require_relative "sidekiq_vigil/middleware/server"
require_relative "sidekiq_vigil/reporter"

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
