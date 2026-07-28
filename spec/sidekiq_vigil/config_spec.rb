# frozen_string_literal: true

RSpec.describe SidekiqVigil::Config do
  it "uses safe defaults without configuration" do
    config = described_class.new(environment: "development")

    expect(config.enabled?).to be(true)
    expect(config.checks.map(&:name)).to include(:queue_latency, :redis_health)
    expect(config.checks.map(&:name)).not_to include(:throughput_anomaly)
    expect(config.runnable_notifiers.map(&:name)).to eq([:log])
  end

  it "allows external notifiers in production" do
    config = described_class.new(environment: "production")
    config.notifier(:slack, webhook_url: "https://hooks.slack.test/a")

    expect(config.runnable_notifiers.map(&:name)).to eq([:slack])
  end

  it "allows an explicit opt-in outside production" do
    config = described_class.new(environment: "test")
    config.enabled = true
    config.notifier(:webhook, url: "https://example.test/events")

    expect(config.runnable_notifiers.map(&:name)).to eq([:webhook])
  end

  it "supports the documented DSL and replaces a default check" do
    config = described_class.new(environment: "production")
    config.check(:queue_latency, warn: 60, critical: 300, queues: :all)
    config.check(:throughput_anomaly, drop_pct: 0.5, baseline_days: 7)
    config.alerting do |alerting|
      alerting.pending_cycles = 3
    end

    expect(config.validate!.checks.find { |item| item.name == :queue_latency }.options[:warn]).to eq(60)
    expect(config.checks.map(&:name).count(:queue_latency)).to eq(1)
    expect(config.alerting.pending_cycles).to eq(3)
  end

  it "accepts custom check and notifier classes" do
    check_class = Class.new(SidekiqVigil::Check::Base)
    notifier_class = Class.new
    stub_const("ExampleHealthCheck", check_class)
    stub_const("ExampleNotifier", notifier_class)
    config = described_class.new

    config.check(ExampleHealthCheck, foo: 1)
    config.notifier(ExampleNotifier)

    expect(config.checks.last.klass).to eq(check_class)
    expect(config.notifiers.last.klass).to eq(notifier_class)
  end

  it "rejects unknown checks and negative thresholds" do
    config = described_class.new

    expect { config.check(:unknown) }.to raise_error(SidekiqVigil::ConfigError, /unknown check/)
    config.check(:queue_size, warn: -1)
    expect { config.validate! }.to raise_error(SidekiqVigil::ConfigError, /must not be negative/)
  end

  it "rejects plain-text Slack mentions with actionable guidance" do
    config = described_class.new(environment: "production")
    config.notifier(:slack, webhook_url: "https://hooks.slack.test/a", mention: { critical: "@oncall" })

    expect { config.validate! }.to raise_error(
      SidekiqVigil::ConfigError,
      /use <@U…>, <!subteam\^S…>, or <!here>/
    )
  end

  it "accepts supported Slack mention formats" do
    config = described_class.new(environment: "production")
    config.notifier(:slack, mention: { warn: "<!here>", critical: "<!subteam^S012ABC>" })

    expect(config.validate!).to be(config)
  end

  it "produces stable digests and reflects behavior changes" do
    first = described_class.new
    second = described_class.new

    expect(first.digest).to eq(second.digest)
    second.interval = 60
    expect(first.digest).not_to eq(second.digest)
  end
end
