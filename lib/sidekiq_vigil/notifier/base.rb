# frozen_string_literal: true

module SidekiqVigil
  module Notifier
    class Base
      attr_reader :options, :logger

      def initialize(options: {}, logger: SidekiqVigil.logger, **_dependencies)
        @options = options
        @logger = logger
      end

      def notify(_event)
        raise NotImplementedError, "#{self.class} must implement #notify"
      end

      def inspect
        "#<#{self.class} options=[FILTERED]>"
      end
    end
  end
end
