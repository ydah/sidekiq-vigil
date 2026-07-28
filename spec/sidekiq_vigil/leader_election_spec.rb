# frozen_string_literal: true

RSpec.describe SidekiqVigil::LeaderElection, :redis do
  it "elects only one leader and allows explicit handoff" do
    first = described_class.new(storage:, ttl: 2, token: "first")
    second = described_class.new(storage:, ttl: 2, token: "second")

    expect(first.acquire).to be(true)
    expect(second.acquire).to be(false)
    expect(first.release).to be(true)
    expect(second.acquire).to be(true)
  end

  it "extends only its own lock" do
    leader = described_class.new(storage:, ttl: 2, token: "owner")
    stranger = described_class.new(storage:, ttl: 2, token: "stranger")
    leader.acquire

    expect(leader.extend).to be(true)
    expect(stranger.extend).to be(false)
  end

  it "fails over after expiration" do
    first = described_class.new(storage:, ttl: 0.05, token: "first")
    second = described_class.new(storage:, ttl: 1, token: "second")
    first.acquire
    sleep(0.06)

    expect(second.acquire).to be(true)
  end
end
