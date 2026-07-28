# frozen_string_literal: true

module SidekiqVigil
  module Check
    class StuckJobs < Base
      def call
        stuck = api.workers.filter_map { |worker| stuck_result(worker) }
        return stuck unless stuck.empty?

        [Result.new(check_name:, severity: :ok, value: 0, threshold: threshold, message: "no stuck jobs")]
      end

      private

      def stuck_result(worker)
        payload = worker.fetch(:work)
        started_at = payload["run_at"] || payload[:run_at]
        return unless started_at

        age = clock.call.to_f - started_at.to_f
        return if age < threshold

        Result.new(
          check_name:,
          target: "#{worker[:process_id]}:#{worker[:thread_id]}",
          severity: :critical,
          value: age,
          threshold:,
          message: "job has run for #{age.round}s",
          metadata: { payload: safe_payload(payload) }
        )
      end

      def safe_payload(payload)
        raw = payload["payload"] || payload[:payload] || {}
        { class: raw["class"] || raw[:class], queue: raw["queue"] || raw[:queue] }
      end

      def threshold
        options.fetch(:threshold, 1_800)
      end
    end
  end
end
