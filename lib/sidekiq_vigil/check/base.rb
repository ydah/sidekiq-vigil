# frozen_string_literal: true

module SidekiqVigil
  module Check
    class Base
      attr_reader :storage, :options, :clock, :logger, :api

      def initialize(storage:, options: {}, clock: -> { Time.now }, logger: SidekiqVigil.logger, api: SidekiqApi.new)
        @storage = storage
        @options = options
        @clock = clock
        @logger = logger
        @api = api
      end

      def execute
        Array(call)
      rescue StandardError => e
        logger.error("[sidekiq-vigil] #{check_name} failed: #{e.class}: #{e.message}")
        [Result.new(
          check_name:,
          severity: :error,
          message: "#{e.class}: #{e.message}",
          metadata: { exception_class: e.class.name }
        )]
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      def check_name
        class_name = self.class.name || "custom_check"
        class_name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      private

      def threshold_result(target:, value:, warn:, critical:, message: nil, metadata: {})
        severity, threshold = severity_and_threshold(value, warn, critical)
        Result.new(check_name:, target:, severity:, value:, threshold:, message:, metadata:)
      end

      def severity_and_threshold(value, warn, critical)
        return [:critical, critical] if critical && value >= critical
        return [:warn, warn] if warn && value >= warn

        [:ok, warn]
      end
    end
  end
end
