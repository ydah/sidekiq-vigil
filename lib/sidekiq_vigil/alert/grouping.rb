# frozen_string_literal: true

module SidekiqVigil
  module Alert
    module Grouping
      module_function

      def apply(events, threshold:, timestamp:, limit: 5)
        return events if events.length <= threshold

        [DigestEvent.new(events:, timestamp:, limit:)]
      end
    end
  end
end
