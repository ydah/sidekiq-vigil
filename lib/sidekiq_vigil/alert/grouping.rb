# frozen_string_literal: true

module SidekiqVigil
  module Alert
    module Grouping
      module_function

      def apply(events, threshold:, timestamp:)
        return events if events.length <= threshold

        [DigestEvent.new(events:, timestamp:)]
      end
    end
  end
end
