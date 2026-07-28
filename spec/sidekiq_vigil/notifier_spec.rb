# frozen_string_literal: true

class NotifierTransportStub
  attr_reader :requests

  def initialize(*responses)
    @responses = responses
    @requests = []
  end

  def post(url, body, headers: {})
    requests << { url:, body: JSON.parse(body), headers: }
    response = @responses.shift || SidekiqVigil::Notifier::HttpTransport::Response.new(code: "200", body: "ok")
    raise response if response.is_a?(Exception)

    response
  end
end

RSpec.describe "notifiers" do
  let(:timestamp) { Time.utc(2026, 7, 28, 12, 0) }
  let(:state) do
    SidekiqVigil::Alert::State.new(
      status: "firing",
      severity: "critical",
      first_seen_at: timestamp.to_f - 3_661
    )
  end
  let(:slack_options) do
    {
      webhook_url: "https://hooks.slack.test/default",
      environment: "production",
      host: "worker-1",
      web_ui_url: "https://example.test/sidekiq",
      mention: { critical: "<!here>" }
    }
  end
  let(:result) do
    SidekiqVigil::Result.new(
      check_name: "queue_size",
      target: "critical",
      severity: :critical,
      value: 100,
      threshold: 50,
      message: "queue too deep"
    )
  end

  def event(transition: :firing, result: self.result)
    SidekiqVigil::Alert::Event.new(
      result:,
      transition:,
      state:,
      history: [{ "value" => 1 }, { "value" => 5 }, { "value" => 3 }],
      timestamp:
    )
  end

  def notification_cases
    warn_result = SidekiqVigil::Result.new(
      check_name: "queue_latency",
      target: "default",
      severity: :warn,
      value: 75,
      threshold: 60,
      message: "queue latency is high"
    )
    resolved_result = SidekiqVigil::Result.new(
      check_name: "queue_size",
      target: "critical",
      severity: :ok,
      value: 0,
      threshold: 50,
      message: "queue depth recovered"
    )
    critical = event
    warn = event(result: warn_result)

    {
      critical:,
      warn:,
      resolved: event(transition: :resolved, result: resolved_result),
      still_firing: event(transition: :still_firing),
      digest: SidekiqVigil::Alert::DigestEvent.new(events: [critical, warn], timestamp:)
    }
  end

  it "matches and posts fixed Block Kit snapshots for all five notification shapes" do
    notification_cases.each do |name, notification|
      url = "https://hooks.slack.test/#{name}"
      slack = SidekiqVigil::Notifier::Slack.new(options: slack_options.merge(webhook_url: url))
      fixture = JSON.parse(File.read(File.join(__dir__, "../fixtures/slack/#{name}.json")))
      payload = JSON.parse(JSON.generate(slack.payload(notification)))
      request = stub_request(:post, url).with(body: fixture).to_return(status: 200, body: "ok")

      expect(payload).to eq(fixture)
      expect(slack.notify(notification)).to be(true)
      expect(request).to have_been_requested.once
    end
  end

  it "routes severities to separate webhook URLs" do
    transport = NotifierTransportStub.new
    slack = SidekiqVigil::Notifier::Slack.new(
      options: { routes: { critical: "https://hooks.slack.test/incidents" } },
      transport:
    )

    expect(slack.notify(event)).to be(true)
    expect(transport.requests.first[:url]).to eq("https://hooks.slack.test/incidents")
  end

  it "retries with exponential backoff and falls back to log" do
    failed = SidekiqVigil::Notifier::HttpTransport::Response.new(code: "500", body: "no")
    transport = NotifierTransportStub.new(failed, failed, failed, failed)
    logger = instance_double(Logger, error: nil)
    fallback = instance_double(SidekiqVigil::Notifier::Log, notify: true)
    sleeps = []
    slack = SidekiqVigil::Notifier::Slack.new(
      options: { webhook_url: "https://hooks.slack.test/secret", retries: 3 },
      logger:,
      transport:,
      sleeper: ->(seconds) { sleeps << seconds },
      fallback:
    )
    notification = event

    expect(slack.notify(notification)).to be(false)
    expect(sleeps).to eq([1, 2, 4])
    expect(fallback).to have_received(:notify).with(notification)
    expect(logger).to have_received(:error).with(satisfy { |message| !message.include?("https://hooks.slack.test/secret") })
  end

  it "masks notifier secrets in inspect output" do
    config = SidekiqVigil::Config.new(environment: "production")
    config.notifier(
      :slack,
      webhook_url: "https://hooks.slack.test/secret",
      routes: { critical: "https://hooks.slack.test/incidents" }
    )

    inspected = config.notifiers.first.inspect
    expect(inspected).to include("[FILTERED]")
    expect(inspected).not_to include("hooks.slack.test")
    expect(SidekiqVigil::Notifier::Slack.new(options: config.notifiers.first.options).inspect).not_to include("secret")
  end

  it "posts the documented event object through the generic webhook" do
    transport = NotifierTransportStub.new
    webhook = SidekiqVigil::Notifier::Webhook.new(
      options: { url: "https://events.example.test/vigil", headers: { "X-Test" => "yes" } },
      transport:
    )

    expect(webhook.notify(event)).to be(true)
    request = transport.requests.first
    expect(request[:body]).to include("schema_version" => "1.0", "event" => "firing")
    expect(request[:body].fetch("alert")).to include("check_name" => "queue_size")
  end

  it "isolates a broken notifier from the remaining notifiers" do
    broken = Class.new do
      def notify(_event)
        raise "broken"
      end
    end.new
    healthy = instance_double(SidekiqVigil::Notifier::Log, notify: true)
    logger = instance_double(Logger, error: nil)
    manager = SidekiqVigil::Notifier::Manager.new(notifiers: [broken, healthy], logger:)
    notification = event

    manager.notify([notification])

    expect(healthy).to have_received(:notify).with(notification)
    expect(logger).to have_received(:error).with(/failed/)
  end
end
