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
          matched = active_schedule?(schedule.fetch(:cron), duration)
          return schedule.fetch(:reason, "scheduled maintenance") if matched
        end
        nil
      end

      def active_schedule?(expression, duration)
        current = clock.call
        current_minute = Time.at((current.to_f / 60).floor * 60)
        cron = Cron.new(expression)
        minute_count = (duration / 60.0).ceil

        (0..minute_count).any? do |offset|
          start_time = current_minute - (offset * 60)
          next false unless current.to_f < start_time.to_f + duration

          cron.match?(Timezone.local_time(start_time, timezone))
        end
      end
    end
  end
end
