# frozen_string_literal: true

module SidekiqVigil
  class Result
    SEVERITIES = %i[ok warn critical error].freeze

    attr_reader :check_name, :target, :severity, :value, :threshold, :message, :metadata

    def initialize(check_name:, severity:, target: "global", value: nil, threshold: nil, message: nil, metadata: {})
      severity = severity.to_sym
      raise ArgumentError, "unknown severity: #{severity}" unless SEVERITIES.include?(severity)

      @check_name = check_name.to_s
      @target = target.to_s
      @severity = severity
      @value = value
      @threshold = threshold
      @message = message
      @metadata = metadata.freeze
      freeze
    end

    def ok?
      severity == :ok
    end

    def alert_id
      "#{check_name}:#{target}"
    end

    def to_h
      {
        check_name: check_name,
        target: target,
        severity: severity,
        value: value,
        threshold: threshold,
        message: message,
        metadata: metadata
      }
    end
  end
end
