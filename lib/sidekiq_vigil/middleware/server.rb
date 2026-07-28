# frozen_string_literal: true

module SidekiqVigil
  module Middleware
    class Server
      include Sidekiq::ServerMiddleware if defined?(Sidekiq::ServerMiddleware)

      def initialize(collector: SidekiqVigil.collector, monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @collector = collector
        @monotonic_clock = monotonic_clock
      end

      def call(worker, job, queue)
        started_at = monotonic_clock.call
        failed = false
        begin
          yield
        rescue Exception # rubocop:disable Lint/RescueException
          failed = true
          raise
        ensure
          record(worker, job, queue, started_at, failed)
        end
      end

      private

      attr_reader :collector, :monotonic_clock

      def record(worker, _job, queue, started_at, failed)
        collector.record(worker:, queue:, duration: monotonic_clock.call - started_at, failed:)
      rescue StandardError => e
        SidekiqVigil.logger.error("[sidekiq-vigil] collector failed: #{e.class}: #{e.message}")
      end
    end
  end
end
