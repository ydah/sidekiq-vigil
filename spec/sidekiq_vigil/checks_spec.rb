# frozen_string_literal: true

CheckQueueStub = Data.define(:name, :size, :latency)
CheckScheduledStub = Data.define(:at)

class CheckApiStub
  attr_accessor :queue_items, :retry_count, :dead_count, :process_items, :worker_items, :scheduled_items

  def initialize
    @queue_items = []
    @retry_count = 0
    @dead_count = 0
    @process_items = []
    @worker_items = []
    @scheduled_items = []
  end

  def queues(_names = :all)
    queue_items
  end

  def retry_size
    retry_count
  end

  def dead_size
    dead_count
  end

  def processes
    process_items
  end

  def workers
    worker_items
  end

  def scheduled
    scheduled_items
  end
end

RSpec.describe "built-in checks", :redis do
  let(:api) { CheckApiStub.new }
  let(:now) { Time.utc(2026, 7, 28, 12, 34) }
  let(:clock) { -> { now } }
  let(:vigil_storage) { storage(prefix: "checks") }

  def execute(klass, options = {}, **extra)
    klass.new(storage: vigil_storage, api:, clock:, options:, **extra).execute
  end

  it "checks per-queue latency with queue overrides and boundaries" do
    api.queue_items = [
      CheckQueueStub.new(name: "default", size: 0, latency: 60),
      CheckQueueStub.new(name: "critical", size: 0, latency: 60)
    ]

    results = execute(
      SidekiqVigil::Check::QueueLatency,
      { warn: 60, critical: 300, per_queue: { "critical" => { warn: 10, critical: 50 } } }
    )

    expect(results.map(&:severity)).to eq(%i[warn critical])
  end

  it "checks queue size and handles no queues" do
    api.queue_items = [CheckQueueStub.new(name: "default", size: 10_000, latency: 0)]
    expect(execute(SidekiqVigil::Check::QueueSize).first.severity).to eq(:critical)

    api.queue_items = []
    expect(execute(SidekiqVigil::Check::QueueSize)).to be_empty
  end

  it "checks retry and dead set growth against the previous value" do
    api.retry_count = 100
    first = execute(SidekiqVigil::Check::RetrySet, { growth_only: true, warn: 10 }).first
    api.retry_count = 115
    second = execute(SidekiqVigil::Check::RetrySet, { growth_only: true, warn: 10 }).first
    api.dead_count = 1
    dead = execute(SidekiqVigil::Check::DeadSet).first

    expect(first.value).to eq(0)
    expect(second).to have_attributes(value: 15, severity: :warn)
    expect(dead.severity).to eq(:warn)
  end

  it "requires the configured number of active processes and ignores stale quiet ones" do
    api.process_items = [
      { "busy" => 1, "concurrency" => 5 },
      { "quiet_since" => now.to_f - 1_000, "busy" => 0, "concurrency" => 5 }
    ]

    result = execute(SidekiqVigil::Check::ProcessAlive, { min_processes: 2, quiet_threshold: 900 }).first

    expect(result).to have_attributes(severity: :critical, value: 1)
  end

  it "alerts only after utilization is sustained" do
    api.process_items = [{ "busy" => 9, "concurrency" => 10 }]
    first = execute(SidekiqVigil::Check::Utilization, { warn: 0.8, critical: 0.95, sustained: 300 }).first
    later_clock = -> { now + 301 }
    result = SidekiqVigil::Check::Utilization.new(
      storage: vigil_storage,
      api:,
      clock: later_clock,
      options: { warn: 0.8, critical: 0.95, sustained: 300 }
    ).execute.first

    expect(first.severity).to eq(:ok)
    expect(result.severity).to eq(:warn)
  end

  it "calculates failure rate with a minimum sample guard" do
    key = "stats:#{now.strftime('%Y%m%d%H%M')}"
    vigil_storage.hash_write(key, { "processed" => 100, "failed" => 20 }, ttl: 60)

    result = execute(
      SidekiqVigil::Check::FailureRate,
      { warn: 0.05, critical: 0.2, window: 60, min_samples: 20 }
    ).first

    expect(result).to have_attributes(severity: :critical, value: 0.2)
    expect(result.message).to include("attempts")
  end

  it "returns OK when failure-rate samples are insufficient" do
    result = execute(SidekiqVigil::Check::FailureRate, { window: 60, min_samples: 20 }).first

    expect(result.severity).to eq(:ok)
    expect(result.metadata[:insufficient_samples]).to be(true)
  end

  it "detects stuck workers without exposing job arguments" do
    api.worker_items = [{
      process_id: "host:1",
      thread_id: "thread",
      work: { "run_at" => now.to_f - 2_000, "payload" => { "class" => "SlowJob", "args" => ["secret"] } }
    }]

    result = execute(SidekiqVigil::Check::StuckJobs, { threshold: 1_800 }).first

    expect(result.severity).to eq(:critical)
    expect(result.metadata.dig(:payload, :class)).to eq("SlowJob")
    expect(result.metadata.to_s).not_to include("secret")
  end

  it "reads reporter RSS values and handles no reporters" do
    expect(execute(SidekiqVigil::Check::Memory).first.severity).to eq(:ok)
    vigil_storage.set("mem:host:1", 2_048_000, ttl: 60)

    result = execute(SidekiqVigil::Check::Memory, { warn_mb: 1_500, critical_mb: 2_500 }).first

    expect(result).to have_attributes(severity: :warn, value: 2_000.0)
  end

  it "measures Redis latency and maxmemory usage" do
    allow(vigil_storage).to receive(:ping).and_return("PONG")
    allow(vigil_storage).to receive(:info).with("memory").and_return(
      "used_memory" => "90",
      "maxmemory" => "100"
    )
    monotonic = [1.0, 1.2].each

    results = execute(
      SidekiqVigil::Check::RedisHealth,
      { latency_ms: 100, memory_pct: 0.8 },
      monotonic_clock: -> { monotonic.next }
    )

    expect(results.map(&:severity)).to eq(%i[warn warn])
  end

  it "turns Redis failures into an error result" do
    allow(vigil_storage).to receive(:ping).and_raise(RedisClient::CannotConnectError, "down")
    logger = instance_double(Logger, error: nil)

    result = SidekiqVigil::Check::RedisHealth.new(
      storage: vigil_storage,
      api:,
      clock:,
      logger:
    ).execute.first

    expect(result.severity).to eq(:error)
  end

  it "counts overdue scheduled jobs" do
    api.scheduled_items = [CheckScheduledStub.new(at: now - 301), CheckScheduledStub.new(at: now + 60)]

    result = execute(SidekiqVigil::Check::ScheduledBacklog, { overdue: 300 }).first

    expect(result).to have_attributes(value: 1, severity: :warn)
  end

  it "guards throughput anomaly until enough baseline samples exist" do
    result = execute(SidekiqVigil::Check::ThroughputAnomaly, { min_samples: 3, timezone: "UTC" }).first

    expect(result.metadata[:insufficient_samples]).to be(true)
  end

  it "detects a throughput drop against the median baseline" do
    3.times do |offset|
      baseline_time = now - ((offset + 1) * 86_400)
      vigil_storage.hash_write(
        "stats:#{baseline_time.strftime('%Y%m%d%H%M')}",
        { "processed" => 100 + (offset * 10) },
        ttl: 8 * 86_400
      )
    end
    vigil_storage.hash_write("stats:#{now.strftime('%Y%m%d%H%M')}", { "processed" => 20 }, ttl: 8 * 86_400)

    result = execute(
      SidekiqVigil::Check::ThroughputAnomaly,
      { min_samples: 3, baseline_days: 3, drop_pct: 0.5, timezone: "UTC" }
    ).first

    expect(result).to have_attributes(severity: :warn, value: 20)
    expect(result.metadata[:baseline]).to eq(110.0)
  end
end
