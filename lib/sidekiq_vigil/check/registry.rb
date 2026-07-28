# frozen_string_literal: true

module SidekiqVigil
  module Check
    class Registry
      def initialize
        @checks = {}
      end

      def register(name, klass)
        @checks[name.to_sym] = klass
      end

      def fetch(name)
        @checks.fetch(name.to_sym)
      end

      def names
        @checks.keys
      end
    end
  end
end
