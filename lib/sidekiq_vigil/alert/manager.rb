# frozen_string_literal: true

require "json"
require "time"

module SidekiqVigil
  module Alert
    class Manager
      HISTORY_TTL = 24 * 60 * 60

      def initialize(storage:, config:, mute:, clock: -> { Time.now })
        @storage = storage
        @config = config
        @mute = mute
        @clock = clock
      end

      def process(results)
        persisted = storage.hash_get_all("alerts")
        active_ids = results.map(&:alert_id)
        muted = mute.active?
        events = results.filter_map { |result| process_result(result, persisted, muted) }
        prune(persisted.keys - active_ids)
        Grouping.apply(events, threshold: config.group_threshold, timestamp: now, limit: config.group_top_n)
      end

      private

      attr_reader :storage, :config, :mute, :clock

      def process_result(result, persisted, muted)
        state = State.load(persisted.fetch(result.alert_id, "{}"))
        refresh_flapping(state)
        record_history(result)
        event = transition(result, state)
        event ||= unsuppressed_event(result, state) unless muted
        state.suppressed = true if event && muted
        persist(result.alert_id, state)
        muted ? nil : event
      end

      def transition(result, state)
        case state.status
        when "ok" then transition_from_ok(result, state)
        when "pending" then transition_from_pending(result, state)
        when "firing" then transition_from_firing(result, state)
        when "resolved" then transition_from_resolved(result, state)
        else reset_invalid_state(result, state)
        end
      end

      def transition_from_ok(result, state)
        return update_ok(state, result) if result.ok?

        begin_pending(state, result)
        fire(result, state, :firing) if state.cycles >= config.pending_cycles
      end

      def transition_from_pending(result, state)
        return update_ok(state, result) if result.ok?

        state.cycles += 1
        update_observation(state, result)
        return if flapping_active?(state)

        fire(result, state, :firing) if state.cycles >= config.pending_cycles
      end

      def transition_from_firing(result, state)
        if result.ok?
          previous_severity = state.severity
          change_status(state, "resolved")
          state.suppressed = false
          state.severity = previous_severity
          return build_event(result, :resolved, state) if config.resolve_notice

          return nil
        end

        state.cycles += 1
        previous_severity = state.severity
        effective = escalated_result(result, state)
        update_observation(state, effective)
        return fire(effective, state, :escalated) if effective.severity.to_s != previous_severity
        return unless cooldown_elapsed?(state)

        fire(effective, state, :still_firing)
      end

      def transition_from_resolved(result, state)
        return update_ok(state, result) if result.ok?

        begin_pending(state, result)
        if flapping?(state)
          state.flapping_until = now.to_f + config.flap_window
          return if state.flap_notified

          state.flap_notified = true
          return build_event(result, :flapping, state)
        end

        fire(result, state, :firing) if state.cycles >= config.pending_cycles
      end

      def begin_pending(state, result)
        change_status(state, "pending")
        state.cycles = 1
        state.first_seen_at = now.to_f
        update_observation(state, result)
      end

      def fire(result, state, transition)
        change_status(state, "firing")
        state.last_notified_at = now.to_f
        state.suppressed = false
        state.flapping_until = nil
        build_event(result, transition, state)
      end

      def update_ok(state, result)
        change_status(state, "ok")
        state.cycles = 0
        state.first_seen_at = nil
        state.severity = "ok"
        state.suppressed = false
        update_observation(state, result)
        nil
      end

      def update_observation(state, result)
        state.severity = result.severity.to_s
        state.value = result.value
        state.threshold = result.threshold
        state.message = result.message
      end

      def escalated_result(result, state)
        threshold = config.escalate_after
        return result unless threshold && result.severity == :warn && state.cycles >= threshold

        Result.new(
          **result.to_h,
          severity: :critical,
          metadata: result.metadata.merge(escalated: true)
        )
      end

      def cooldown_elapsed?(state)
        now.to_f - state.last_notified_at.to_f >= config.cooldown
      end

      def unsuppressed_event(result, state)
        return unless state.firing? && state.suppressed

        state.suppressed = false
        fire(result, state, :unmuted)
      end

      def build_event(result, transition, state)
        Event.new(
          result:,
          transition:,
          state:,
          history: storage.list_range("history:#{result.alert_id}").map { |item| JSON.parse(item) },
          timestamp: now
        )
      end

      def record_history(result)
        point = JSON.generate(timestamp: now.to_f, value: result.value, severity: result.severity)
        storage.list_push("history:#{result.alert_id}", point, ttl: HISTORY_TTL)
      end

      def persist(alert_id, state)
        storage.managed_hash_write("alerts", alert_id, state.dump)
      end

      def prune(alert_ids)
        storage.hash_delete("alerts", *alert_ids)
        alert_ids.each { |alert_id| storage.delete("history:#{alert_id}") }
      end

      def reset_invalid_state(result, state)
        state.status = "ok"
        transition_from_ok(result, state)
      end

      def change_status(state, status)
        return if state.status == status

        state.status = status
        state.last_transition_at = now.to_f
        state.transition_timestamps << now.to_f
        prune_transition_timestamps(state)
      end

      def flapping?(state)
        return false unless config.flap_window.positive? && config.flap_threshold.positive?

        prune_transition_timestamps(state)
        state.transition_timestamps.length >= config.flap_threshold
      end

      def flapping_active?(state)
        state.flapping_until && now.to_f < state.flapping_until
      end

      def refresh_flapping(state)
        prune_transition_timestamps(state)
        return if flapping_active?(state)
        return if state.transition_timestamps.length >= config.flap_threshold

        state.flapping_until = nil
        state.flap_notified = false
      end

      def prune_transition_timestamps(state)
        cutoff = now.to_f - config.flap_window
        state.transition_timestamps.select! { |timestamp| timestamp.to_f >= cutoff }
      end

      def now
        clock.call
      end
    end
  end
end
