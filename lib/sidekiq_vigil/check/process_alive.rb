# frozen_string_literal: true

module SidekiqVigil
  module Check
    class ProcessAlive < Base
      def call
        processes = api.processes
        minimum = options.fetch(:min_processes, 1)
        active = processes.count { |process| active?(process) }
        severity = active < minimum ? :critical : :ok

        Result.new(
          check_name:,
          severity:,
          value: active,
          threshold: minimum,
          message: "#{active}/#{minimum} required processes alive",
          metadata: { total: processes.size }
        )
      end

      private

      def active?(process)
        quiet_since = process_value(process, "quiet_since")
        return clock.call.to_f - quiet_since.to_f < quiet_threshold if quiet_since

        unless stopping?(process)
          clear_quiet_state(process)
          return true
        end

        state_key = "check_state:quiet:#{process_identity(process)}"
        observed_at = storage.get(state_key)
        storage.set(state_key, observed_at || clock.call.to_f, ttl: quiet_threshold + 3_600)
        observed_at.nil? || clock.call.to_f - observed_at.to_f < quiet_threshold
      end

      def process_value(process, key)
        process[key] || process[key.to_sym]
      end

      def stopping?(process)
        return process.stopping? if process.respond_to?(:stopping?)

        %w[true 1].include?(process_value(process, "quiet").to_s)
      end

      def clear_quiet_state(process)
        storage.delete("check_state:quiet:#{process_identity(process)}")
      end

      def process_identity(process)
        return process.identity if process.respond_to?(:identity)

        process_value(process, "identity") || process.object_id
      end

      def quiet_threshold
        options.fetch(:quiet_threshold, 900)
      end
    end
  end
end
