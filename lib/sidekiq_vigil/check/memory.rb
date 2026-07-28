# frozen_string_literal: true

module SidekiqVigil
  module Check
    class Memory < Base
      def call
        return [skipped_result] if RUBY_PLATFORM.match?(/mswin|mingw/)

        keys = storage.scan("mem:*")
        return [empty_result] if keys.empty?

        keys.map do |key|
          process_id = key.delete_prefix(storage.prefix).delete_prefix("mem:")
          value_mb = storage.get("mem:#{process_id}").to_f / 1024
          threshold_result(
            target: process_id,
            value: value_mb,
            warn: options.fetch(:warn_mb, 1_500),
            critical: options.fetch(:critical_mb, 2_500),
            message: format("%.1f MiB RSS", value_mb)
          )
        end
      end

      private

      def skipped_result
        Result.new(
          check_name:,
          severity: :ok,
          message: "memory collection is unsupported on Windows",
          metadata: { skipped: true }
        )
      end

      def empty_result
        Result.new(check_name:, severity: :ok, value: 0, message: "no process RSS reports")
      end
    end
  end
end
