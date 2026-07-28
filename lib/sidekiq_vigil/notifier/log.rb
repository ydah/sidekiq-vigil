# frozen_string_literal: true

require "json"

module SidekiqVigil
  module Notifier
    class Log < Base
      def notify(event)
        logger.warn("[sidekiq-vigil] #{JSON.generate(event.to_h)}")
        true
      end
    end
  end
end
