# frozen_string_literal: true

module SidekiqVigil
  module Check
    class QueueSize < Base
      def call
        api.queues(options.fetch(:queues, :all)).map do |queue|
          thresholds = options.merge(options.fetch(:per_queue, {}).fetch(queue.name, {}))
          threshold_result(
            target: queue.name,
            value: queue.size,
            warn: thresholds.fetch(:warn, 1_000),
            critical: thresholds.fetch(:critical, 10_000),
            message: "#{queue.size} jobs waiting"
          )
        end
      end
    end
  end
end
