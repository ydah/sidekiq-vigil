# frozen_string_literal: true

require "rbconfig"
require "timeout"

RSpec.describe "Sidekiq Vigil end to end", :e2e do
  let(:redis_url) { ENV.fetch("VIGIL_REDIS_URL", "redis://127.0.0.1:16379/14") }
  let(:redis) { RedisClient.config(url: redis_url).new_client }

  before do
    redis.call("FLUSHDB")
    Sidekiq.configure_client { |config| config.redis = { url: redis_url } }
  end

  it "receives digest and resolved Block Kit events from an actual Sidekiq process" do
    server = MockHttpServer.new
    Sidekiq::Client.push("class" => "VigilE2EJob", "queue" => "vigil_e2e_a", "args" => [])
    Sidekiq::Client.push("class" => "VigilE2EJob", "queue" => "vigil_e2e_b", "args" => [])
    Sidekiq::Client.push("class" => "VigilE2EJob", "queue" => "vigil_e2e_c", "args" => [])
    Sidekiq::Client.push("class" => "VigilE2EJob", "queue" => "vigil_e2e_d", "args" => [])
    Sidekiq::Client.push("class" => "VigilE2EJob", "queue" => "vigil_e2e_worker", "args" => ["fail"])
    sleep(1.1)
    fixture = File.expand_path("../fixtures/e2e_worker.rb", __dir__)
    pid = Process.spawn(
      {
        "REDIS_URL" => redis_url,
        "VIGIL_REDIS_URL" => redis_url,
        "MOCK_SLACK_URL" => server.url,
        "RACK_ENV" => "test"
      },
      RbConfig.ruby,
      "-S",
      "bundle",
      "exec",
      "sidekiq",
      "-r",
      fixture,
      "-q",
      "vigil_e2e_worker",
      "-c",
      "1",
      out: ENV.fetch("VIGIL_E2E_LOG", File::NULL),
      err: ENV.fetch("VIGIL_E2E_LOG", File::NULL)
    )

    digest = next_message(server, prefix: "📦 DIGEST")
    expect(digest.fetch("text")).to start_with("📦 DIGEST")

    Sidekiq::Queue.new("vigil_e2e_a").clear
    resolved = next_message(server, prefix: "✅ RESOLVED")
    expect(resolved.fetch("text")).to start_with("✅ RESOLVED")
  ensure
    terminate(pid)
    server&.stop
  end

  it "delivers a direct Redis outage notification after its connection target stops" do
    slack = MockHttpServer.new
    stopped_target = TCPServer.new("127.0.0.1", 0)
    port = stopped_target.local_address.ip_port
    stopped_target.close
    config = SidekiqVigil::Config.new(environment: "test")
    config.enabled = true
    config.interval = 1
    config.key_prefix = "e2e-outage"
    config.redis = { url: "redis://127.0.0.1:#{port}/15", timeout: 0.1 }
    config.checks.clear
    config.notifier :slack, webhook_url: slack.url, retries: 0
    checker = SidekiqVigil::Checker.new(storage: SidekiqVigil.build_storage(config), config:)

    expect(checker.run_once).to be(false)
    payload = next_message(slack)
    expect(payload.fetch("text")).to include("redis_health")
  ensure
    slack&.stop
  end

  def next_message(server, prefix: nil)
    observed = []
    Timeout.timeout(15) do
      loop do
        message = server.messages.pop
        return message unless prefix
        return message if message.fetch("text").start_with?(prefix)

        observed << message.fetch("text")
      end
    end
  rescue Timeout::Error
    raise Timeout::Error, "waiting for #{prefix.inspect}; observed #{observed.inspect}"
  end

  def terminate(pid)
    return unless pid

    Process.kill("TERM", pid)
    Timeout.timeout(10) { Process.wait(pid) }
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  rescue Timeout::Error
    Process.kill("KILL", pid)
    Process.wait(pid)
  end
end
