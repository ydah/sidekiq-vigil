# frozen_string_literal: true

require "rack/test"

RSpec.describe SidekiqVigil::HealthApp, :redis do
  include Rack::Test::Methods

  let(:now) { Time.utc(2026, 7, 28, 12, 0) }
  let(:vigil_storage) { storage(prefix: "health") }
  let(:app) { described_class.new(storage: vigil_storage, interval: 30, clock: -> { now }) }

  def write_snapshot(timestamp:, severities: ["ok"])
    payload = {
      timestamp: timestamp.iso8601,
      results: severities.map.with_index do |severity, index|
        { check_name: "check_#{index}", target: "global", severity: }
      end
    }
    vigil_storage.set("snapshot", JSON.generate(payload), ttl: 120)
  end

  it "returns 200 only for an all-OK fresh snapshot" do
    write_snapshot(timestamp: now - 60, severities: %w[ok ok])

    get "/healthz"

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include("healthy" => true, "fresh" => true)
  end

  it "returns 503 for stale or unhealthy snapshots" do
    write_snapshot(timestamp: now - 61)
    get "/healthz"
    expect(last_response.status).to eq(503)

    write_snapshot(timestamp: now, severities: %w[ok warn])
    get "/healthz"
    expect(last_response.status).to eq(503)
  end

  it "returns detailed status and age" do
    write_snapshot(timestamp: now - 10)

    get "/status.json"
    body = JSON.parse(last_response.body)

    expect(last_response.status).to eq(200)
    expect(body).to include("age_seconds" => 10.0, "fresh" => true)
    expect(body.fetch("results").first).to include("check_name" => "check_0")
  end

  it "fails closed when the snapshot is missing or malformed" do
    get "/healthz"
    expect(last_response.status).to eq(503)

    vigil_storage.set("snapshot", "not-json", ttl: 120)
    get "/healthz"
    expect(last_response.status).to eq(503)
  end

  it "rejects unsupported routes and methods" do
    post "/healthz"
    expect(last_response.status).to eq(405)
    get "/missing"
    expect(last_response.status).to eq(404)
  end
end
