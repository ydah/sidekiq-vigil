# frozen_string_literal: true

module SidekiqVigil
  module Check
    class RedisHealth < Base
      def initialize(
        storage:,
        options: {},
        clock: -> { Time.now },
        logger: SidekiqVigil.logger,
        api: SidekiqApi.new,
        monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      )
        super(storage:, options:, clock:, logger:, api:)
        @monotonic_clock = monotonic_clock
      end

      def call
        started_at = monotonic_clock.call
        storage.ping
        latency_ms = (monotonic_clock.call - started_at) * 1_000
        [latency_result(latency_ms), memory_result]
      end

      private

      attr_reader :monotonic_clock

      def latency_result(latency_ms)
        threshold_result(
          target: "latency",
          value: latency_ms,
          warn: options.fetch(:latency_ms, 100),
          critical: options.fetch(:critical_latency_ms, options.fetch(:latency_ms, 100) * 2),
          message: format("%.2fms PING latency", latency_ms)
        )
      end

      def memory_result
        info = storage.info("memory")
        used = info.fetch("used_memory", 0).to_f
        maximum = info.fetch("maxmemory", 0).to_f
        ratio = maximum.positive? ? used / maximum : 0.0
        threshold_result(
          target: "memory",
          value: ratio,
          warn: options.fetch(:memory_pct, 0.9),
          critical: options.fetch(:critical_memory_pct, 0.98),
          message: maximum.positive? ? format("%.1f%% Redis maxmemory used", ratio * 100) : "Redis maxmemory is unlimited",
          metadata: { used_memory: used.to_i, maxmemory: maximum.to_i }
        )
      end
    end
  end
end
