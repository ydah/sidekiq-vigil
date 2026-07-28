# frozen_string_literal: true

class CheckerTestCheck < SidekiqVigil::Check::Base
  class << self
    attr_accessor :calls
  end
  self.calls = 0

  def call
    self.class.calls += 1
    SidekiqVigil::Result.new(check_name: "test", severity: options.fetch(:severity, :ok), value: 1)
  end
end

RSpec.describe SidekiqVigil::Checker, :redis do
  let(:config) do
    SidekiqVigil::Config.new(environment: "test").tap do |value|
      value.checks.clear
      value.check(CheckerTestCheck)
    end
  end
  let(:vigil_storage) { storage(prefix: "checker") }
  let(:leader) { instance_double(SidekiqVigil::LeaderElection, leader?: false, acquire: true, extend: true, release: true) }
  let(:alert_manager) { instance_double(SidekiqVigil::Alert::Manager, process: []) }
  let(:notifier_manager) { instance_double(SidekiqVigil::Notifier::Manager, notify: nil) }
  let(:logger) { instance_double(Logger, error: nil, warn: nil) }
  subject(:checker) do
    described_class.new(
      storage: vigil_storage,
      config:,
      leader_election: leader,
      alert_manager:,
      notifier_manager:,
      logger:
    )
  end

  before do
    CheckerTestCheck.calls = 0
  end

  it "runs checks only as leader and refreshes a timestamped snapshot" do
    results = checker.run_once
    first_snapshot = JSON.parse(vigil_storage.get("snapshot"))

    expect(results.first.check_name).to eq("test")
    expect(first_snapshot).to include("timestamp", "results")
    expect(CheckerTestCheck.calls).to eq(1)
    expect(notifier_manager).to have_received(:notify)
  end

  it "builds its default alert manager with the injected clock" do
    instance = described_class.new(
      storage: vigil_storage,
      config:,
      leader_election: leader,
      notifier_manager:,
      logger:,
      clock: -> { Time.utc(2026, 7, 28, 12) }
    )

    expect(instance.run_once).to be_an(Array)
  end

  it "does not execute checks when leadership is held elsewhere" do
    allow(leader).to receive(:acquire).and_return(false)

    expect(checker.run_once).to be(false)
    expect(CheckerTestCheck.calls).to eq(0)
    expect(vigil_storage.get("snapshot")).to be_nil
  end

  it "logs configuration drift without stopping the cycle" do
    vigil_storage.hash_write("config_digest", { "a" => "one", "b" => "two" }, ttl: 60)

    expect(checker.run_once).to be_an(Array)
    expect(logger).to have_received(:warn).with(/configuration digest mismatch/)
  end

  it "contains cycle failures and continues on the next invocation" do
    allow(alert_manager).to receive(:process).and_raise("manager failed")

    expect(checker.run_once).to be(false)
    allow(alert_manager).to receive(:process).and_return([])
    expect(checker.run_once).to be_an(Array)
    expect(CheckerTestCheck.calls).to eq(2)
  end

  it "uses the Redis-independent direct notification path once per outage" do
    allow(leader).to receive(:acquire).and_raise(RedisClient::CannotConnectError, "connection refused")

    2.times { expect(checker.run_once).to be(false) }

    expect(notifier_manager).to have_received(:notify).once do |events|
      expect(events.first.result.check_name).to eq("redis_health")
      expect(events.first.result.severity).to eq(:error)
    end
  end

  it "releases leadership when the checker thread exits" do
    sleeper = ->(_seconds) { raise "stop loop" }
    instance = described_class.new(
      storage: vigil_storage,
      config:,
      leader_election: leader,
      alert_manager:,
      notifier_manager:,
      logger:,
      sleeper:
    )

    instance.start.join

    expect(leader).to have_received(:release)
    expect(logger).to have_received(:error).with(/checker thread failed/)
  end
end
