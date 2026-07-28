# frozen_string_literal: true

require "json"
require "time"

module SidekiqVigil
  class Checker
    attr_reader :thread

    def initialize(
      storage:,
      config:,
      leader_election: nil,
      alert_manager: nil,
      notifier_manager: nil,
      logger: SidekiqVigil.logger,
      clock: -> { Time.now },
      sleeper: ->(seconds) { sleep(seconds) }
    )
      @storage = storage
      @config = config
      @logger = logger
      @clock = clock
      @sleeper = sleeper
      @leader_election = leader_election || LeaderElection.new(storage:, ttl: config.interval * 3)
      @notifier_manager = notifier_manager || build_notifier_manager
      @alert_manager = alert_manager || build_alert_manager
      @running = false
      @direct_redis_notified = false
    end

    def start
      return thread if thread&.alive?

      @running = true
      @thread = Thread.new { run }
      @thread.name = "sidekiq-vigil-checker" if @thread.respond_to?(:name=)
      @thread
    end

    def stop
      @running = false
      thread&.wakeup if thread&.status == "sleep"
      thread&.join(config.interval + 1)
      leader_election.release
      @thread = nil
    end

    def run_once
      return false unless become_or_remain_leader

      results = configured_checks.flat_map(&:execute)
      write_snapshot(results)
      warn_config_drift
      notifier_manager.notify(alert_manager.process(results))
      @direct_redis_notified = false
      results
    rescue StandardError => e
      logger.error("[sidekiq-vigil] checker cycle failed: #{e.class}: #{e.message}")
      notify_redis_outage(e) if redis_error?(e)
      false
    end

    private

    attr_reader :storage, :config, :leader_election, :alert_manager, :notifier_manager, :logger, :clock, :sleeper

    def run
      while @running
        run_once
        sleeper.call(config.interval)
      end
    rescue StandardError => e
      logger.error("[sidekiq-vigil] checker thread failed: #{e.class}: #{e.message}")
    ensure
      leader_election.release
    end

    def become_or_remain_leader
      return leader_election.extend if leader_election.leader?

      leader_election.acquire
    end

    def configured_checks
      config.checks.map do |definition|
        klass = definition.klass || BUILT_IN_CHECKS.fetch(definition.name)
        options = definition.options.merge(timezone: config.timezone)
        klass.new(storage:, options:, clock:, logger:)
      end
    end

    def write_snapshot(results)
      payload = JSON.generate(timestamp: clock.call.utc.iso8601, results: results.map(&:to_h))
      storage.set("snapshot", payload, ttl: config.interval * 4)
    end

    def warn_config_drift
      digests = storage.hash_get_all("config_digest")
      return if digests.values.uniq.length <= 1

      logger.warn("[sidekiq-vigil] configuration digest mismatch across processes")
    end

    def build_notifier_manager
      Notifier::Manager.new(notifiers: Notifier::Factory.build(config, logger:), logger:)
    end

    def build_alert_manager
      mute = Alert::Mute.new(
        storage:,
        schedules: config.alerting.mutes,
        clock:,
        timezone: config.timezone
      )
      Alert::Manager.new(storage:, config: config.alerting, mute:, clock:)
    end

    def notify_redis_outage(error)
      return if @direct_redis_notified

      @direct_redis_notified = true
      result = Result.new(
        check_name: "redis_health",
        target: "connection",
        severity: :error,
        message: "Redis unavailable (#{error.class})"
      )
      state = Alert::State.new(status: "firing", severity: "error", message: result.message)
      event = Alert::Event.new(result:, transition: :firing, state:, history: [], timestamp: clock.call)
      notifier_manager.notify([event])
    end

    def redis_error?(error)
      return true if defined?(RedisClient::Error) && error.is_a?(RedisClient::Error)

      error.message.match?(/redis|connection|socket|timeout/i)
    end
  end
end
