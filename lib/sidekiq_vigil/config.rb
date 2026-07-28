# frozen_string_literal: true

require "digest"
require "json"

module SidekiqVigil
  class ConfigError < Error; end

  class Config
    CheckDefinition = Data.define(:name, :klass, :options)
    class NotifierDefinition
      SECRET_KEYS = %i[webhook_url routes bot_token url].freeze

      attr_reader :name, :klass, :options

      def initialize(name:, klass:, options:)
        @name = name
        @klass = klass
        @options = options
      end

      def inspect
        safe_options = options.transform_values.with_index do |value, _index|
          value.is_a?(Hash) ? value.transform_values { "[FILTERED]" } : value
        end
        SECRET_KEYS.each { |key| safe_options[key] = "[FILTERED]" if safe_options.key?(key) }
        "#<#{self.class} name=#{name.inspect} options=#{safe_options.inspect}>"
      end
    end

    BUILT_IN_CHECKS = %i[
      queue_latency queue_size retry_set dead_set process_alive utilization failure_rate stuck_jobs memory redis_health
      scheduled_backlog throughput_anomaly
    ].freeze
    DEFAULT_CHECKS = (BUILT_IN_CHECKS - [:throughput_anomaly]).freeze
    SLACK_MENTION = /\A(?:<@U[A-Z0-9]+>|<!subteam\^S[A-Z0-9]+>|<!here>)\z/

    attr_accessor :interval, :flush_interval, :key_prefix, :timezone, :redis
    attr_reader :checks, :notifiers

    def initialize(environment: nil)
      @environment = environment || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
      @enabled = true
      @enabled_explicit = false
      @interval = 30
      @flush_interval = 10
      @key_prefix = "default"
      @timezone = "UTC"
      @redis = nil
      @checks = DEFAULT_CHECKS.map { |name| CheckDefinition.new(name:, klass: nil, options: {}) }
      @notifiers = []
      @alerting = AlertingConfig.new
    end

    def enabled=(value)
      @enabled_explicit = true
      @enabled = value
    end

    def enabled?
      @enabled == true
    end

    def production?
      environment == "production"
    end

    def external_notifications_enabled?
      production? || (@enabled_explicit && enabled?)
    end

    def check(name_or_class, **options)
      name, klass = normalize_check(name_or_class)
      checks.reject! { |definition| definition.name == name }
      checks << CheckDefinition.new(name:, klass:, options:)
    end

    def disable_check(name)
      checks.reject! { |definition| definition.name == name.to_sym }
    end

    def notifier(name_or_class, **options)
      name, klass = normalize_notifier(name_or_class)
      notifiers << NotifierDefinition.new(name:, klass:, options:)
    end

    def alerting
      yield @alerting if block_given?
      @alerting
    end

    def validate!
      validate_positive!(:interval, interval)
      validate_positive!(:flush_interval, flush_interval)
      raise ConfigError, "key_prefix must not be empty" if key_prefix.to_s.empty?
      raise ConfigError, "key_prefix contains unsupported characters" unless key_prefix.to_s.match?(/\A[\w.-]+\z/)
      raise ConfigError, "timezone must not be empty" if timezone.to_s.empty?

      checks.each { |definition| validate_options!(definition.options, "check #{definition.name}") }
      notifiers.each { |definition| validate_notifier!(definition) }
      alerting.validate!
      self
    end

    def digest
      payload = {
        enabled: enabled?,
        interval: interval,
        flush_interval: flush_interval,
        key_prefix: key_prefix,
        timezone: timezone,
        checks: checks.map { |item| [item.name, item.options] },
        alerting: alerting.to_h
      }
      Digest::SHA256.hexdigest(JSON.generate(payload))
    end

    def runnable_notifiers
      validate!
      definitions = notifiers.empty? ? [NotifierDefinition.new(name: :log, klass: nil, options: {})] : notifiers
      return definitions if external_notifications_enabled?

      definitions.select { |definition| definition.name == :log }
    end

    private

    attr_reader :environment

    def normalize_check(name_or_class)
      if name_or_class.is_a?(Class)
        return [name_or_class.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym,
                name_or_class]
      end

      name = name_or_class.to_sym
      raise ConfigError, "unknown check: #{name}" unless BUILT_IN_CHECKS.include?(name)

      [name, nil]
    end

    def normalize_notifier(name_or_class)
      return [name_or_class.name.split("::").last.downcase.to_sym, name_or_class] if name_or_class.is_a?(Class)

      name = name_or_class.to_sym
      raise ConfigError, "unknown notifier: #{name}" unless %i[log slack webhook].include?(name)

      [name, nil]
    end

    def validate_positive!(name, value)
      raise ConfigError, "#{name} must be positive" unless value.is_a?(Numeric) && value.positive?
    end

    def validate_options!(options, context)
      options.each do |key, value|
        next unless numeric_threshold?(key)
        next if value.is_a?(Numeric) && !value.negative?

        raise ConfigError, "#{context} #{key} must not be negative"
      end
    end

    def numeric_threshold?(key)
      key.to_s.match?(/(?:warn|critical|threshold|overdue|window|samples|processes|sustained|drop_pct|baseline_days|latency_ms|memory_pct)/)
    end

    def validate_notifier!(definition)
      validate_options!(definition.options, "notifier #{definition.name}")
      return unless definition.name == :slack

      mentions = definition.options.fetch(:mention, {})
      mentions.each_value do |mention|
        next if mention.nil? || mention.match?(SLACK_MENTION)

        raise ConfigError,
              "invalid Slack mention #{mention.inspect}; use <@U…>, <!subteam^S…>, or <!here>"
      end
    end
  end

  class AlertingConfig
    attr_accessor :pending_cycles, :cooldown, :resolve_notice, :flap_window, :escalate_after, :group_threshold, :mutes

    def initialize
      @pending_cycles = 2
      @cooldown = 600
      @resolve_notice = true
      @flap_window = 120
      @escalate_after = nil
      @group_threshold = 5
      @mutes = []
    end

    def validate!
      %i[pending_cycles cooldown flap_window group_threshold].each do |name|
        value = public_send(name)
        raise ConfigError, "#{name} must not be negative" unless value.is_a?(Numeric) && !value.negative?
      end
      self
    end

    def to_h
      {
        pending_cycles: pending_cycles,
        cooldown: cooldown,
        resolve_notice: resolve_notice,
        flap_window: flap_window,
        escalate_after: escalate_after,
        group_threshold: group_threshold,
        mutes: mutes
      }
    end
  end
end
