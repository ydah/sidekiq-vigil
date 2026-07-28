# frozen_string_literal: true

RSpec.describe SidekiqVigil::Reporter, :redis do
  let(:collector) { SidekiqVigil::Collector.new(clock: -> { Time.utc(2026, 7, 28, 12, 34) }) }
  let(:config) { SidekiqVigil::Config.new.tap { |value| value.flush_interval = 2 } }
  let(:logger) { instance_double(Logger, error: nil) }
  let(:vigil_storage) { storage }
  subject(:reporter) { described_class.new(storage: vigil_storage, collector:, config:, logger:) }

  it "flushes exact counter aggregates, RSS, and config digest" do
    collector.record(worker: String, queue: "critical", duration: 0.5, failed: true)
    allow(reporter).to receive(:rss_kb).and_return(12_345)

    expect(reporter.flush_once).to be(true)
    expect(vigil_storage.hash_get_all("stats:202607281234")).to include("processed" => "1", "failed" => "1")
    expect(vigil_storage.hash_get_all("exec:critical")).to include("count" => "1", "sum" => "0.5")
    expect(vigil_storage.scan("mem:*").length).to eq(1)
    expect(vigil_storage.hash_get_all("config_digest").values).to eq([config.digest])
  end

  it "restores counters after a failed flush" do
    collector.record(worker: String, queue: "default", duration: 1, failed: false)
    allow(vigil_storage).to receive(:hash_increment).and_raise("redis down")

    expect(reporter.flush_once).to be(false)
    expect(collector.drain.stats["202607281234"]["processed"]).to eq(1)
  end

  it "contains thread failures instead of crashing the host process" do
    sleeper = ->(_seconds) { raise "stop" }
    instance = described_class.new(storage: vigil_storage, collector:, config:, logger:, sleeper:)

    instance.start.join

    expect(logger).to have_received(:error).with(/reporter thread failed/)
  end
end
