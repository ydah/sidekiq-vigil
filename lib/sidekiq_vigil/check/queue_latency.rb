# frozen_string_literal: true

module SidekiqVigil
  module Check
    class QueueLatency < Base
      def call
        api.queues(options.fetch(:queues, :all)).map do |queue|
          thresholds = options.merge(options.fetch(:per_queue, {}).fetch(queue.name, {}))
          latency = queue.latency.to_f
          threshold_result(
            target: queue.name,
            value: latency,
            warn: thresholds.fetch(:warn, 60),
            critical: thresholds.fetch(:critical, 300),
            message: "oldest job has waited #{latency.round(2)}s"
          )
        end
      end
    end
  end
end
