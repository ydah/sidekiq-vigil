# frozen_string_literal: true

RSpec.describe SidekiqVigil::Alert::Manager, :redis do
  let(:time) { [Time.utc(2026, 7, 28, 12, 0)] }
  let(:clock) { -> { time.first } }
  let(:alerting) { SidekiqVigil::AlertingConfig.new }
  let(:mute) { SidekiqVigil::Alert::Mute.new(storage:, clock:) }
  subject(:manager) { described_class.new(storage:, config: alerting, mute:, clock:) }

  def result(severity, target: "default", value: 10)
    SidekiqVigil::Result.new(
      check_name: "queue_size",
      target:,
      severity:,
      value:,
      threshold: 5,
      message: "queue depth is #{value}"
    )
  end

  it "moves through pending, firing, still-firing, resolved, and OK" do
    expect(manager.process([result(:warn)])).to be_empty
    firing = manager.process([result(:warn)])
    time[0] += alerting.cooldown - 1
    expect(manager.process([result(:warn)])).to be_empty
    time[0] += 2
    ongoing = manager.process([result(:warn)])
    resolved = manager.process([result(:ok, value: 0)])
    back_to_ok = manager.process([result(:ok, value: 0)])

    expect(firing.map(&:transition)).to eq([:firing])
    expect(ongoing.map(&:transition)).to eq([:still_firing])
    expect(resolved.map(&:transition)).to eq([:resolved])
    expect(back_to_ok).to be_empty
  end

  it "persists state across manager instances" do
    manager.process([result(:critical)])
    replacement = described_class.new(storage:, config: alerting, mute:, clock:)

    events = replacement.process([result(:critical)])

    expect(events.first.transition).to eq(:firing)
    state = SidekiqVigil::Alert::State.load(storage.hash_get_all("alerts").fetch("queue_size:default"))
    expect(state.status).to eq("firing")
  end

  it "prunes disappeared targets and their history" do
    manager.process([result(:warn, target: "gone")])
    expect(storage.hash_get_all("alerts")).to have_key("queue_size:gone")

    manager.process([])

    expect(storage.hash_get_all("alerts")).to be_empty
    expect(storage.scan("history:*")).to be_empty
  end

  it "keeps a 30-point history with a 24-hour TTL" do
    35.times { |index| manager.process([result(:ok, value: index)]) }

    history = storage.list_range("history:queue_size:default")
    expect(history.length).to eq(30)
    expect(JSON.parse(history.first).fetch("value")).to eq(5)
  end

  it "groups more than the configured threshold into one digest" do
    alerting.pending_cycles = 1
    alerting.group_threshold = 2
    results = 3.times.map { |index| result(:critical, target: "queue-#{index}") }

    events = manager.process(results)

    expect(events.length).to eq(1)
    expect(events.first).to be_a(SidekiqVigil::Alert::DigestEvent)
    expect(events.first.to_h[:counts]).to eq(critical: 3)
  end

  it "does not group at the threshold boundary" do
    alerting.pending_cycles = 1
    alerting.group_threshold = 2
    results = 2.times.map { |index| result(:critical, target: "queue-#{index}") }

    expect(manager.process(results).length).to eq(2)
  end

  it "suppresses notifications while muted and sends current firing state after unmute" do
    alerting.pending_cycles = 1
    mute.mute(60, reason: "deploy")

    expect(manager.process([result(:critical)])).to be_empty
    mute.unmute
    events = manager.process([result(:critical)])

    expect(events.map(&:transition)).to eq([:unmuted])
  end

  it "escalates a sustained warning only once" do
    alerting.pending_cycles = 1
    alerting.escalate_after = 3
    manager.process([result(:warn)])
    time[0] += 1
    expect(manager.process([result(:warn)])).to be_empty
    events = manager.process([result(:warn)])
    immediate_repeat = manager.process([result(:warn)])

    expect(events.first).to have_attributes(transition: :escalated, severity: :critical)
    expect(immediate_repeat).to be_empty
  end

  it "reports rapid recurrence as flapping once" do
    alerting.pending_cycles = 1
    manager.process([result(:critical)])
    manager.process([result(:ok, value: 0)])

    first = manager.process([result(:critical)])
    second = manager.process([result(:critical)])

    expect(first.map(&:transition)).to eq([:flapping])
    expect(second.map(&:transition)).to eq([:firing])
  end
end

RSpec.describe SidekiqVigil::Alert::Mute, :redis do
  it "recognizes configured cron maintenance windows" do
    clock = -> { Time.utc(2026, 7, 26, 3, 30) }
    mute = described_class.new(
      storage:,
      schedules: [{ cron: "0 3 * * 0", duration: 3_600, reason: "weekly maintenance" }],
      clock:,
      timezone: "UTC"
    )

    expect(mute).to be_active
    expect(mute.reason).to eq("weekly maintenance")
  end
end
