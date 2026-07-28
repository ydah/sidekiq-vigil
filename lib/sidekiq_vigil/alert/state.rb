# frozen_string_literal: true

require "json"

module SidekiqVigil
  module Alert
    class State
      ATTRIBUTES = %i[
        status cycles first_seen_at last_notified_at last_transition_at severity value threshold message suppressed
        flap_notified
      ].freeze

      attr_accessor(*ATTRIBUTES)

      def initialize(attributes = {})
        attributes = attributes.transform_keys(&:to_sym)
        @status = attributes.fetch(:status, "ok")
        @cycles = attributes.fetch(:cycles, 0)
        @first_seen_at = attributes[:first_seen_at]
        @last_notified_at = attributes[:last_notified_at]
        @last_transition_at = attributes[:last_transition_at]
        @severity = attributes.fetch(:severity, "ok")
        @value = attributes[:value]
        @threshold = attributes[:threshold]
        @message = attributes[:message]
        @suppressed = attributes.fetch(:suppressed, false)
        @flap_notified = attributes.fetch(:flap_notified, false)
      end

      def self.load(json)
        new(JSON.parse(json))
      rescue JSON::ParserError
        new
      end

      def to_h
        ATTRIBUTES.to_h { |name| [name, public_send(name)] }
      end

      def dump
        JSON.generate(to_h)
      end

      def firing?
        status == "firing"
      end
    end
  end
end
