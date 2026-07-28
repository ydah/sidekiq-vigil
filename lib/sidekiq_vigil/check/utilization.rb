# frozen_string_literal: true

module SidekiqVigil
  module Check
    class Utilization < Base
      STATE_TTL_PADDING = 300

      def call
        busy, concurrency = totals
        ratio = concurrency.zero? ? 0.0 : busy.fdiv(concurrency)
        severity, threshold = sustained_severity(ratio)
        Result.new(
          check_name:,
          severity:,
          value: ratio,
          threshold:,
          message: format(
            "%<ratio>.1f%% utilized (%<busy>d/%<concurrency>d)",
            ratio: ratio * 100,
            busy:,
            concurrency:
          )
        )
      end

      private

      def totals
        api.processes.each_with_object([0, 0]) do |process, totals|
          totals[0] += process_value(process, "busy").to_i
          totals[1] += process_value(process, "concurrency").to_i
        end
      end

      def process_value(process, key)
        process[key] || process[key.to_sym]
      end

      def sustained_severity(ratio)
        warn = options.fetch(:warn, 0.85)
        critical = options.fetch(:critical, 0.95)
        return clear_sustained_state(warn) if ratio < warn

        started_at = storage.get("check_state:utilization_since")
        storage.set("check_state:utilization_since", started_at || clock.call.to_f, ttl: state_ttl)
        return [:ok, warn] if started_at.nil? || clock.call.to_f - started_at.to_f < options.fetch(:sustained, 300)

        severity_and_threshold(ratio, warn, critical)
      end

      def clear_sustained_state(warn)
        storage.delete("check_state:utilization_since")
        [:ok, warn]
      end

      def state_ttl
        options.fetch(:sustained, 300) + STATE_TTL_PADDING
      end
    end
  end
end
