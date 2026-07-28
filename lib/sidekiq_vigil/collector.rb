# frozen_string_literal: true

module SidekiqVigil
  class Collector
    Snapshot = Data.define(:stats, :executions)

    def initialize(clock: -> { Time.now })
      @clock = clock
      @mutex = Mutex.new
      @stats = empty_stats
      @executions = empty_executions
    end

    def record(worker:, queue:, duration:, failed:)
      minute = clock.call.utc.strftime("%Y%m%d%H%M")
      worker_name = worker.respond_to?(:name) ? worker.name : worker.class.name
      @mutex.synchronize do
        update_stats(minute, worker_name, failed)
        update_execution(queue.to_s, duration)
      end
    end

    def drain
      @mutex.synchronize do
        snapshot = Snapshot.new(stats: @stats, executions: @executions)
        @stats = empty_stats
        @executions = empty_executions
        snapshot
      end
    end

    def merge(snapshot)
      @mutex.synchronize do
        snapshot.stats.each do |minute, fields|
          fields.each { |field, value| @stats[minute][field] += value }
        end
        snapshot.executions.each do |queue, values|
          current = @executions[queue]
          current[:count] += values[:count]
          current[:sum] += values[:sum]
          current[:max] = [current[:max], values[:max]].max
        end
      end
    end

    private

    attr_reader :clock

    def empty_stats
      Hash.new { |hash, key| hash[key] = Hash.new(0) }
    end

    def empty_executions
      Hash.new { |hash, key| hash[key] = { count: 0, sum: 0.0, max: 0.0 } }
    end

    def update_stats(minute, worker_name, failed)
      @stats[minute]["processed"] += 1
      @stats[minute]["processed:#{worker_name}"] += 1
      return unless failed

      @stats[minute]["failed"] += 1
      @stats[minute]["failed:#{worker_name}"] += 1
    end

    def update_execution(queue, duration)
      execution = @executions[queue]
      execution[:count] += 1
      execution[:sum] += duration
      execution[:max] = [execution[:max], duration].max
    end
  end
end
