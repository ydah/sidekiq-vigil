# frozen_string_literal: true

require "json"
require "socket"

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
          blocks: event.transition == :digest ? digest_blocks(event) : alert_blocks(event)
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
          markdown_field("*Check*\n#{display(result.check_name)}"),
          markdown_field("*Target*\n#{result.target}"),
          markdown_field("*Value / threshold*\n#{display(result.value)} / #{display(result.threshold)}"),
          markdown_field("*Duration*\n#{duration(event)}"),
          markdown_field("*Environment*\n#{environment}"),
          markdown_field("*Host*\n#{host}")
        ]
      end

      def context_block(event)
        parts = ["Event #{event.transition}"]
        spark = sparkline(event.history)
        parts << "Trend #{spark}" unless spark.empty?
        parts << "<#{options[:web_ui_url]}|Open Sidekiq>" if options[:web_ui_url]
        mentions = options.fetch(:mention, {})
        mention = mentions[event.severity] || mentions[event.severity.to_s]
        parts << mention if mention

        { type: "context", elements: [{ type: "mrkdwn", text: parts.join(" • ") }] }
      end

      def alert_blocks(event)
        [
          header_block(event),
          { type: "section", fields: fields(event) },
          message_block(event.result.message),
          context_block(event)
        ].compact
      end

      def digest_blocks(event)
        metadata = event.result.metadata
        [
          header_block(event),
          { type: "section", text: { type: "mrkdwn", text: digest_counts(metadata.fetch(:counts)) } },
          { type: "section", text: { type: "mrkdwn", text: digest_top(metadata.fetch(:top)) } },
          context_block(event)
        ]
      end

      def header_block(event)
        { type: "header", text: { type: "plain_text", text: header(event) } }
      end

      def message_block(message)
        return unless message

        { type: "section", text: { type: "mrkdwn", text: "*Message*\n#{message}" } }
      end

      def digest_counts(counts)
        labels = { error: "Error", critical: "Critical", warn: "Warn", ok: "OK" }
        values = labels.filter_map do |severity, label|
          count = counts[severity] || counts[severity.to_s]
          "#{label}: #{count}" if count.to_i.positive?
        end
        "*Severity counts*\n#{values.join(' • ')}"
      end

      def digest_top(alerts)
        lines = alerts.map do |alert|
          severity = fetch_value(alert, :severity).to_s.upcase
          check = fetch_value(alert, :check_name)
          target = fetch_value(alert, :target)
          value = display(fetch_value(alert, :value))
          threshold = display(fetch_value(alert, :threshold))
          "• *#{severity}* #{check} / #{target} — #{value} / #{threshold}"
        end
        "*Top alerts*\n#{lines.join("\n")}"
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

      def duration(event)
        started_at = event.state.first_seen_at
        return "-" unless started_at

        seconds = [event.timestamp.to_f - started_at.to_f, 0].max.round
        return "#{seconds}s" if seconds < 60
        return "#{seconds / 60}m #{seconds % 60}s" if seconds < 3_600

        "#{seconds / 3_600}h #{(seconds % 3_600) / 60}m"
      end

      def environment
        options.fetch(:environment) { ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "unknown" }
      end

      def host
        options.fetch(:host) { Socket.gethostname }
      end

      def fetch_value(hash, key)
        hash[key] || hash[key.to_s]
      end

      def safe_error(error)
        error.message.gsub(%r{https?://\S+}, "[FILTERED]")
      end
    end
  end
end
