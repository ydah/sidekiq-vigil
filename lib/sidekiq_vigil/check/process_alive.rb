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
        return true unless quiet_since

        clock.call.to_f - quiet_since.to_f < options.fetch(:quiet_threshold, 900)
      end

      def process_value(process, key)
        process[key] || process[key.to_sym]
      end
    end
  end
end
