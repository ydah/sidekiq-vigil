# frozen_string_literal: true

module SidekiqVigil
  module Check
    class SetSize < Base
      STATE_TTL = 8 * 24 * 60 * 60

      def call
        total = current_size
        value = growth_value(total)
        threshold_result(
          target: "global",
          value:,
          warn: options.fetch(:warn, default_warn),
          critical: options.fetch(:critical, default_critical),
          message: message(total, value),
          metadata: { total: }
        )
      end

      private

      def growth_value(total)
        return total unless options.fetch(:growth_only, false)

        previous = storage.get(state_key)
        storage.set(state_key, total, ttl: STATE_TTL)
        return 0 unless previous

        [total - previous.to_i, 0].max
      end

      def state_key
        "check_state:#{check_name}"
      end

      def message(total, value)
        return "#{total} entries" unless options.fetch(:growth_only, false)

        "#{value} new entries (#{total} total)"
      end
    end

    class RetrySet < SetSize
      private

      def current_size
        api.retry_size
      end

      def default_warn
        100
      end

      def default_critical
        1_000
      end
    end

    class DeadSet < SetSize
      private

      def current_size
        api.dead_size
      end

      def default_warn
        1
      end

      def default_critical
        50
      end
    end
  end
end
