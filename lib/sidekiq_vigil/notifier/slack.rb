# frozen_string_literal: true

require "json"

module SidekiqVigil
  module Notifier
    class Slack < Base
      SPARKS = "▁▂▃▄▅▆▇█"

      def initialize(
        options: {},
        logger: SidekiqVigil.logger,
        transport: HttpTransport.new,
        sleeper: ->(seconds) { sleep(seconds) },
        fallback: Log.new(logger:)
      )
        super(options:, logger:)
        @transport = transport
        @sleeper = sleeper
        @fallback = fallback
      end

      def notify(event)
        attempts = options.fetch(:retries, 3) + 1
        attempts.times do |attempt|
          response = transport.post(webhook_url(event), JSON.generate(payload(event)))
          return true if response.success?

          raise Error, "Slack returned HTTP #{response.code}"
        rescue StandardError => e
          if attempt == attempts - 1
            logger.error("[sidekiq-vigil] Slack notification failed after #{attempts} attempts: #{safe_error(e)}")
            fallback.notify(event)
            return false
          end
          sleeper.call(2**attempt)
        end
      end

      def payload(event)
        {
          text: header(event),
          blocks: [
            { type: "header", text: { type: "plain_text", text: header(event) } },
            { type: "section", fields: fields(event) },
            context_block(event)
          ].compact
        }
      end

      private

      attr_reader :transport, :sleeper, :fallback

      def webhook_url(event)
        routes = options.fetch(:routes, {})
        routes[event.severity] || routes[event.severity.to_s] || options.fetch(:webhook_url)
      end

      def header(event)
        return "📦 DIGEST — #{event.result.message}" if event.transition == :digest
        return "✅ RESOLVED — #{event.result.check_name}" if event.transition == :resolved

        icon = %i[critical error].include?(event.severity) ? "🔥" : "⚠️"
        "#{icon} #{event.severity.to_s.upcase} — #{event.result.check_name}"
      end

      def fields(event)
        result = event.result
        [
          markdown_field("*Target*\n#{result.target}"),
          markdown_field("*Event*\n#{event.transition}"),
          markdown_field("*Value / threshold*\n#{display(result.value)} / #{display(result.threshold)}"),
          markdown_field("*Message*\n#{result.message || '-'}")
        ]
      end

      def context_block(event)
        parts = []
        spark = sparkline(event.history)
        parts << "Trend #{spark}" unless spark.empty?
        parts << "<#{options[:web_ui_url]}|Open Sidekiq>" if options[:web_ui_url]
        mention = options.fetch(:mention, {})[event.severity]
        parts << mention if mention
        return if parts.empty?

        { type: "context", elements: [{ type: "mrkdwn", text: parts.join(" • ") }] }
      end

      def markdown_field(text)
        { type: "mrkdwn", text: }
      end

      def sparkline(history)
        values = history.filter_map { |point| numeric(point["value"] || point[:value]) }
        return "" if values.empty?
        return SPARKS[0] * values.length if values.min == values.max

        values.map do |value|
          index = ((value - values.min) / (values.max - values.min) * (SPARKS.length - 1)).round
          SPARKS[index]
        end.join
      end

      def numeric(value)
        Float(value)
      rescue TypeError, ArgumentError
        nil
      end

      def display(value)
        value.nil? ? "-" : value.to_s
      end

      def safe_error(error)
        error.message.gsub(%r{https?://\S+}, "[FILTERED]")
      end
    end
  end
end
