# frozen_string_literal: true

module SidekiqVigil
  module Notifier
    class Manager
      def initialize(notifiers:, logger: SidekiqVigil.logger)
        @notifiers = notifiers
        @logger = logger
      end

      def notify(events)
        Array(events).each do |event|
          notifiers.each { |notifier| notify_one(notifier, event) }
        end
      end

      private

      attr_reader :notifiers, :logger

      def notify_one(notifier, event)
        notifier.notify(event)
      rescue StandardError => e
        logger.error("[sidekiq-vigil] #{notifier.class} failed: #{e.class}: #{e.message}")
      end
    end

    module Factory
      CLASSES = {
        log: Log,
        slack: Slack,
        webhook: Webhook
      }.freeze

      module_function

      def build(config, logger: SidekiqVigil.logger)
        config.runnable_notifiers.map do |definition|
          klass = definition.klass || CLASSES.fetch(definition.name)
          klass.new(options: definition.options, logger:)
        end
      end
    end
  end
end
