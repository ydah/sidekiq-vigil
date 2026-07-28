# frozen_string_literal: true

require "digest"
require "socket"

module SidekiqVigil
  class Reporter
    STATS_TTL = 8 * 24 * 60 * 60
    EXECUTION_TTL = 60 * 60
    CONFIG_TTL = 60 * 60

    attr_reader :thread

    def initialize(storage:, collector:, config:, logger: SidekiqVigil.logger, sleeper: ->(seconds) { sleep(seconds) })
      @storage = storage
      @collector = collector
      @config = config
      @logger = logger
      @sleeper = sleeper
      @running = false
    end

    def start
      return thread if thread&.alive?

      @running = true
      @thread = Thread.new { run }
      @thread.name = "sidekiq-vigil-reporter" if @thread.respond_to?(:name=)
      @thread
    end

    def stop
      @running = false
      thread&.wakeup if thread&.status == "sleep"
      thread&.join(config.flush_interval + 1)
      @thread = nil
    end

    def flush_once
      snapshot = collector.drain
      flush_snapshot(snapshot)
      report_rss
      storage.hash_write("config_digest", { process_id => config.digest }, ttl: CONFIG_TTL)
      true
    rescue StandardError => e
      collector.merge(snapshot) if snapshot
      logger.error("[sidekiq-vigil] reporter flush failed: #{e.class}: #{e.message}")
      false
    end

    def rss_kb
      return linux_rss if File.readable?("/proc/self/status")
      return macos_rss if RUBY_PLATFORM.include?("darwin")

      nil
    end

    private

    attr_reader :storage, :collector, :config, :logger, :sleeper

    def run
      while @running
        flush_once
        sleeper.call(config.flush_interval)
      end
    rescue StandardError => e
      logger.error("[sidekiq-vigil] reporter thread failed: #{e.class}: #{e.message}")
    end

    def flush_snapshot(snapshot)
      snapshot.stats.each do |minute, fields|
        storage.hash_increment("stats:#{minute}", fields, ttl: STATS_TTL)
      end
      snapshot.executions.each do |queue, values|
        storage.hash_increment("exec:#{queue}", values.transform_keys(&:to_s), ttl: EXECUTION_TTL)
      end
    end

    def report_rss
      rss = rss_kb
      return unless rss

      storage.set("mem:#{process_id}", rss, ttl: config.flush_interval * 3)
    end

    def process_id
      @process_id ||= "#{Socket.gethostname}:#{Process.pid}"
    end

    def linux_rss
      match = File.read("/proc/self/status").match(/^VmRSS:\s+(\d+)\s+kB/)
      match && Integer(match[1])
    end

    def macos_rss
      output = IO.popen(["ps", "-o", "rss=", "-p", Process.pid.to_s], &:read)
      Integer(output.strip, exception: false)
    rescue StandardError
      nil
    end
  end
end
