# frozen_string_literal: true

require "json"

module SidekiqVigil
  module Notifier
    class Webhook < Base
      def initialize(options: {}, logger: SidekiqVigil.logger, transport: HttpTransport.new)
        super(options:, logger:)
        @transport = transport
      end

      def notify(event)
        response = transport.post(options.fetch(:url), JSON.generate(event.to_h), headers: options.fetch(:headers, {}))
        raise Error, "webhook returned HTTP #{response.code}" unless response.success?

        true
      end

      private

      attr_reader :transport
    end
  end
end
