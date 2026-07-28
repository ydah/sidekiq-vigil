# frozen_string_literal: true

require "json"

module SidekiqVigil
  module Alert
    class Mute
      def initialize(storage:, schedules: [], clock: -> { Time.now }, timezone: "UTC")
        @storage = storage
        @schedules = schedules
        @clock = clock
        @timezone = timezone
      end

      def active?
        !reason.nil?
      end

      def reason
        dynamic_reason || scheduled_reason
      end

      def mute(duration, reason: nil)
        payload = JSON.generate(reason: reason || "manual mute", until: clock.call.to_f + duration)
        storage.set("mute", payload, ttl: duration)
      end

      def unmute
        storage.delete("mute")
      end

      private

      attr_reader :storage, :schedules, :clock, :timezone

      def dynamic_reason
        payload = storage.get("mute")
        return unless payload

        JSON.parse(payload).fetch("reason")
      rescue JSON::ParserError
        "manual mute"
      end

      def scheduled_reason
        schedules.each do |schedule|
          duration = schedule.fetch(:duration)
          minutes = (duration / 60.0).ceil
          matched = (0..minutes).any? do |offset|
            candidate = Timezone.local_time(clock.call - (offset * 60), timezone)
            cron_match?(schedule.fetch(:cron), candidate)
          end
          return schedule.fetch(:reason, "scheduled maintenance") if matched
        end
        nil
      end

      def cron_match?(expression, time)
        fields = expression.split
        raise ConfigError, "mute cron must contain five fields" unless fields.length == 5

        values = [time.min, time.hour, time.day, time.month, time.wday]
        fields.zip(values).all? { |field, value| field == "*" || field.split(",").map(&:to_i).include?(value) }
      end
    end
  end
end
