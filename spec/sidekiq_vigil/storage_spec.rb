# frozen_string_literal: true

RSpec.describe SidekiqVigil::Storage, :redis do
  subject(:vigil_storage) { storage(prefix: "myapp") }

  it "prefixes every key and applies a ttl to strings" do
    vigil_storage.set("snapshot", "{}", ttl: 60)

    expect(redis.call("GET", "vigil:myapp:snapshot")).to eq("{}")
    expect(redis.call("TTL", "vigil:myapp:snapshot")).to be_between(1, 60)
  end

  it "supports fractional ttl values for short checker intervals" do
    vigil_storage.set("short", "value", ttl: 0.5)

    expect(redis.call("PTTL", vigil_storage.key("short"))).to be_between(1, 500)
  end

  it "rejects writes without a positive ttl" do
    expect { vigil_storage.set("unsafe", "x", ttl: nil) }.to raise_error(described_class::MissingTTL)
    expect { vigil_storage.hash_write("unsafe", { "a" => 1 }, ttl: 0) }.to raise_error(described_class::MissingTTL)
  end

  it "increments hashes in a pipeline and retains expiry" do
    vigil_storage.hash_increment("stats:202607281200", { "processed" => 2, "duration" => 1.5 }, ttl: 90)
    vigil_storage.hash_increment("stats:202607281200", { "processed" => 3 }, ttl: 90)

    expect(vigil_storage.hash_get_all("stats:202607281200")).to include("processed" => "5", "duration" => "1.5")
    expect(redis.call("TTL", vigil_storage.key("stats:202607281200"))).to be_positive
  end

  it "keeps only the configured history length" do
    4.times { |index| vigil_storage.list_push("history:a", index, ttl: 60, limit: 3) }

    expect(vigil_storage.list_range("history:a")).to eq(%w[1 2 3])
  end

  it "allows explicitly managed persistent alert state" do
    vigil_storage.managed_hash_write("alerts", "queue_size:default", "{}")

    expect(vigil_storage.hash_get_all("alerts")).to have_key("queue_size:default")
    expect(redis.call("TTL", vigil_storage.key("alerts"))).to eq(-1)
  end

  it "rejects persistent writes outside the explicitly managed alerts hash" do
    expect do
      vigil_storage.managed_hash_write("other", "field", "value")
    end.to raise_error(described_class::UnmanagedPersistentKey, /only alerts/)
    expect do
      vigil_storage.acquire_lock("leader", "token", ttl_ms: 0)
    end.to raise_error(described_class::MissingTTL)
  end

  it "scans only its own namespace" do
    vigil_storage.set("mem:a", 1, ttl: 60)
    redis.call("SET", "other:key", "x", "EX", 60)

    expect(vigil_storage.scan("mem:*")).to eq([vigil_storage.key("mem:a")])
  end

  it "keeps the public Redis key document identical to the executable catalog" do
    document = File.read(File.expand_path("../../docs/redis_keys.md", __dir__))
    documented = document.scan(/^\| `([^`]+)` \|/).flatten

    expect(documented).to eq(described_class::KEY_CATALOG.map(&:pattern))
  end
end
