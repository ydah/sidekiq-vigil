# frozen_string_literal: true

module SidekiqVigil
  module Check
    class FailureRate < Base
      def call
        processed, failed = counts
        rate = processed.zero? ? 0.0 : failed.fdiv(processed)
        return insufficient_samples(processed, rate) if processed < options.fetch(:min_samples, 20)

        threshold_result(
          target: "global",
          value: rate,
          warn: options.fetch(:warn, 0.05),
          critical: options.fetch(:critical, 0.20),
          message: format("%<rate>.1f%% failures (%<failed>d/%<processed>d attempts)", rate: rate * 100, failed:, processed:),
          metadata: { processed:, failed: }
        )
      end

      private

      def counts
        minute_count = (options.fetch(:window, 300) / 60.0).ceil
        minute_count.times.each_with_object([0, 0]) do |offset, totals|
          key = "stats:#{(clock.call - (offset * 60)).utc.strftime('%Y%m%d%H%M')}"
          stats = storage.hash_get_all(key)
          totals[0] += stats.fetch("processed", 0).to_i
          totals[1] += stats.fetch("failed", 0).to_i
        end
      end

      def insufficient_samples(processed, rate)
        Result.new(
          check_name:,
          severity: :ok,
          value: rate,
          threshold: options.fetch(:warn, 0.05),
          message: "insufficient samples (#{processed}/#{options.fetch(:min_samples, 20)})",
          metadata: { processed:, insufficient_samples: true }
        )
      end
    end
  end
end
