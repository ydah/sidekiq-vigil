# frozen_string_literal: true

RSpec.describe "webhook JSON schema" do
  let(:schema) do
    JSON.parse(File.read(File.expand_path("../../docs/webhook_event.schema.json", __dir__)))
  end
  let(:event) do
    result = SidekiqVigil::Result.new(check_name: "queue_size", severity: :critical)
    state = SidekiqVigil::Alert::State.new(status: "firing", severity: "critical")
    SidekiqVigil::Alert::Event.new(
      result:,
      transition: :firing,
      state:,
      history: [],
      timestamp: Time.utc(2026, 7, 28, 12)
    )
  end

  it "keeps regular events aligned with the published required fields and enums" do
    payload = JSON.parse(JSON.generate(event.to_h))
    required = schema.fetch("required")
    event_enum = schema.dig("properties", "event", "enum")
    severity_enum = schema.dig("properties", "alert", "properties", "severity", "enum")

    expect(payload.keys).to include(*required)
    expect(event_enum).to include(payload.fetch("event"))
    expect(payload.fetch("alert").keys).to include(*schema.dig("properties", "alert", "required"))
    expect(severity_enum).to include(payload.dig("alert", "severity"))
  end

  it "keeps digest events aligned with the published conditional fields" do
    digest = SidekiqVigil::Alert::DigestEvent.new(events: [event], timestamp: Time.utc(2026, 7, 28, 12))
    payload = JSON.parse(JSON.generate(digest.to_h))

    expect(payload).to include("event" => "digest", "alert_id" => "digest")
    expect(payload.keys).to include("counts", "alerts")
  end
end
