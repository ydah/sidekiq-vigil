# frozen_string_literal: true

module SidekiqVigil
  module Check
    class ScheduledBacklog < Base
      def call
        overdue_count = api.scheduled.count do |job|
          timestamp = job.respond_to?(:at) ? job.at : Time.at(job.score.to_f)
          timestamp <= clock.call - options.fetch(:overdue, 300)
        end
        threshold_result(
          target: "global",
          value: overdue_count,
          warn: options.fetch(:warn, 1),
          critical: options.fetch(:critical, 100),
          message: "#{overdue_count} overdue scheduled jobs"
        )
      end
    end
  end
end
