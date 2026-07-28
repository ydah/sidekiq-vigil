# frozen_string_literal: true

module SidekiqVigil
  module Alert
    class Event
      attr_reader :result, :transition, :state, :history, :timestamp

      def initialize(result:, transition:, state:, history:, timestamp:)
        @result = result
        @transition = transition.to_sym
        @state = state
        @history = history
        @timestamp = timestamp
      end

      def severity
        result.severity
      end

      def alert_id
        result.alert_id
      end

      def to_h
        {
          schema_version: "1.0",
          event: transition,
          alert_id:,
          timestamp: timestamp.utc.iso8601,
          alert: result.to_h,
          state: state.to_h,
          history:
        }
      end
    end

    class DigestEvent
      attr_reader :events, :timestamp

      def initialize(events:, timestamp:, limit: 5)
        @events = events
        @timestamp = timestamp
        @limit = limit
      end

      def transition
        :digest
      end

      def severity
        severities.include?(:critical) || severities.include?(:error) ? :critical : :warn
      end

      def alert_id
        "digest"
      end

      def result
        @result ||= Result.new(
          check_name: "digest",
          severity:,
          value: events.length,
          message: "#{events.length} alerts in this cycle",
          metadata: { counts: counts, top: top }
        )
      end

      def history
        []
      end

      def state
        State.new(status: "firing", severity: severity.to_s)
      end

      def to_h
        {
          schema_version: "1.0",
          event: "digest",
          alert_id:,
          timestamp: timestamp.utc.iso8601,
          counts:,
          alerts: top
        }
      end

      private

      attr_reader :limit

      def severities
        events.map(&:severity)
      end

      def counts
        events.group_by(&:severity).transform_values(&:length)
      end

      def top
        events.sort_by { |event| severity_rank(event.severity) }.first(limit).map do |event|
          event.result.to_h
        end
      end

      def severity_rank(severity)
        { error: 0, critical: 1, warn: 2, ok: 3 }.fetch(severity, 4)
      end
    end
  end
end
