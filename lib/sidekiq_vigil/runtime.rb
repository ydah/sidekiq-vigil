# frozen_string_literal: true

module SidekiqVigil
  class Runtime
    attr_reader :reporter, :checker

    def initialize(
      config:,
      storage:,
      collector: SidekiqVigil.collector,
      logger: SidekiqVigil.logger,
      reporter: nil,
      checker: nil
    )
      @config = config
      @reporter = reporter || Reporter.new(storage:, collector:, config:, logger:)
      @checker = checker || Checker.new(storage:, config:, logger:)
    end

    def start
      return false unless config.enabled?

      reporter.start
      checker.start
      true
    rescue StandardError => e
      SidekiqVigil.logger.error("[sidekiq-vigil] startup failed: #{e.class}: #{e.message}")
      false
    end

    def quiet
      checker.stop
    end

    def stop
      checker.stop
      reporter.stop
    end

    private

    attr_reader :config
  end
end
