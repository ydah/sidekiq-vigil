# frozen_string_literal: true

require "json"
require "time"

module SidekiqVigil
  class HealthApp
    JSON_HEADERS = { "content-type" => "application/json", "cache-control" => "no-store" }.freeze

    def initialize(storage:, interval:, clock: -> { Time.now })
      @storage = storage
      @interval = interval
      @clock = clock
    end

    def call(env)
      return response(405, error: "method not allowed") unless env["REQUEST_METHOD"] == "GET"

      case env["PATH_INFO"]
      when "/healthz" then health
      when "/status.json" then status
      else response(404, error: "not found")
      end
    rescue StandardError => e
      response(503, healthy: false, error: "snapshot unavailable", detail: e.class.name)
    end

    private

    attr_reader :storage, :interval, :clock

    def health
      report = snapshot_report
      response(report[:healthy] ? 200 : 503, report.slice(:healthy, :fresh, :age_seconds))
    end

    def status
      report = snapshot_report
      response(report[:healthy] ? 200 : 503, report)
    end

    def snapshot_report
      raw = storage.get("snapshot")
      return { healthy: false, fresh: false, age_seconds: nil, error: "snapshot missing" } unless raw

      snapshot = JSON.parse(raw)
      age = clock.call - Time.iso8601(snapshot.fetch("timestamp"))
      fresh = age <= interval * 2
      checks_ok = snapshot.fetch("results").all? { |result| result.fetch("severity") == "ok" }
      snapshot.merge(healthy: checks_ok && fresh, fresh:, age_seconds: age.round(3))
    end

    def response(status, body)
      [status, JSON_HEADERS, [JSON.generate(body)]]
    end
  end
end
