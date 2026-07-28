# frozen_string_literal: true

RSpec.describe SidekiqVigil::Collector do
  subject(:collector) { described_class.new(clock: -> { Time.utc(2026, 7, 28, 12, 34) }) }

  it "tracks processed, failed, worker, and execution aggregates" do
    collector.record(worker: String, queue: "default", duration: 0.5, failed: false)
    collector.record(worker: String, queue: "default", duration: 1.5, failed: true)

    snapshot = collector.drain
    expect(snapshot.stats["202607281234"]).to include(
      "processed" => 2,
      "processed:String" => 2,
      "failed" => 1,
      "failed:String" => 1
    )
    expect(snapshot.executions["default"]).to eq(count: 2, sum: 2.0, max: 1.5)
    expect(collector.drain.stats).to be_empty
  end

  it "does not lose increments under concurrent writes" do
    threads = 10.times.map do
      Thread.new do
        100.times { collector.record(worker: String, queue: "bulk", duration: 0.01, failed: false) }
      end
    end
    threads.each(&:join)

    expect(collector.drain.stats["202607281234"]["processed"]).to eq(1000)
  end

  it "merges a drained snapshot back after a failed flush" do
    collector.record(worker: String, queue: "default", duration: 1, failed: false)
    snapshot = collector.drain
    collector.merge(snapshot)

    expect(collector.drain.stats["202607281234"]["processed"]).to eq(1)
  end
end

RSpec.describe SidekiqVigil::Middleware::Server do
  let(:collector) { instance_double(SidekiqVigil::Collector, record: nil) }
  let(:clock) { [1.0, 1.25].each }
  subject(:middleware) { described_class.new(collector:, monotonic_clock: -> { clock.next }) }

  it "records successful execution without Redis access" do
    expect(middleware.call(String, {}, "default") { :ok }).to eq(:ok)
    expect(collector).to have_received(:record).with(
      worker: String,
      queue: "default",
      duration: 0.25,
      failed: false
    )
  end

  it "records and reraises job failures" do
    expect { middleware.call(String, {}, "default") { raise "job failed" } }.to raise_error("job failed")
    expect(collector).to have_received(:record).with(hash_including(failed: true))
  end

  it "isolates collector failures from job execution" do
    allow(collector).to receive(:record).and_raise("collector unavailable")
    allow(SidekiqVigil.logger).to receive(:error)

    expect(middleware.call(String, {}, "default") { :done }).to eq(:done)
  end
end
