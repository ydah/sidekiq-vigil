# frozen_string_literal: true

require "rbconfig"
require "English"
require "stringio"
require "timeout"
require "tmpdir"

class CliCheckerStub
  attr_reader :started, :stopped

  def initialize(results)
    @results = results
  end

  def run_once
    @results
  end

  def start
    @started = true
  end

  def stop
    @stopped = true
  end
end

RSpec.describe SidekiqVigil::CLI, :redis do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:config) { SidekiqVigil.config }
  let(:vigil_storage) { storage(prefix: "cli") }

  def cli(checker = nil)
    factory = checker && -> { checker }
    described_class.new(config:, storage: vigil_storage, out:, err:, checker_factory: factory)
  end

  it "runs a one-shot check and returns alert status" do
    result = SidekiqVigil::Result.new(check_name: "queue_size", severity: :warn, message: "large")
    status = cli(CliCheckerStub.new([result])).run(%w[check --once])

    expect(status).to eq(described_class::EXIT_ALERT)
    expect(out.string).to include("WARN\tqueue_size")
  end

  it "requires the explicit oneshot flag" do
    status = cli(CliCheckerStub.new([])).run(["check"])

    expect(status).to eq(described_class::EXIT_UNAVAILABLE)
    expect(err.string).to include("requires --once")
  end

  it "prints the latest status snapshot" do
    vigil_storage.set(
      "snapshot",
      JSON.generate(
        timestamp: "2026-07-28T12:00:00Z",
        results: [{ severity: "ok", check_name: "queue_size", target: "default" }],
        alerts: { "queue_size:default" => { status: "firing" } }
      ),
      ttl: 60
    )

    expect(cli.run(["status"])).to eq(described_class::EXIT_OK)
    expect(out.string).to include("Snapshot: 2026-07-28T12:00:00Z", "OK\tqueue_size\tdefault\tFIRING")
  end

  it "creates and clears a manual mute" do
    expect(cli.run(%w[mute 5m --reason deploy])).to eq(described_class::EXIT_OK)
    expect(JSON.parse(vigil_storage.get("mute")).fetch("reason")).to eq("deploy")

    expect(cli.run(["unmute"])).to eq(described_class::EXIT_OK)
    expect(vigil_storage.get("mute")).to be_nil
  end

  it "loads a pure Ruby configuration without Rails" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "vigil.rb")
      File.write(path, <<~RUBY)
        SidekiqVigil.configure do |config|
          config.interval = 17
          config.checks.clear
        end
      RUBY

      status = cli(CliCheckerStub.new([])).run(["--config", path, "check", "--once"])

      expect(status).to eq(described_class::EXIT_OK)
      expect(config.interval).to eq(17)
    end
  end

  it "rejects invalid commands and durations" do
    expect(cli.run(["unknown"])).to eq(described_class::EXIT_UNAVAILABLE)
    expect(cli.run(%w[mute later])).to eq(described_class::EXIT_UNAVAILABLE)
  end

  it "exits cleanly after SIGTERM in standalone mode" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "vigil.rb")
      File.write(path, <<~RUBY)
        SidekiqVigil.configure do |config|
          config.interval = 0.1
          config.key_prefix = "cli-child"
          config.redis = {
            url: ENV.fetch("VIGIL_REDIS_URL", "redis://127.0.0.1:16379/15")
          }
          config.checks.clear
        end
      RUBY
      pid = Process.spawn(
        RbConfig.ruby,
        "-I#{File.expand_path('../../lib', __dir__)}",
        File.expand_path("../../exe/vigil", __dir__),
        "--config",
        path,
        out: File::NULL,
        err: File::NULL
      )
      Timeout.timeout(5) do
        sleep(0.05) until redis.call("EXISTS", "vigil:cli-child:leader") == 1
      end
      Process.kill("TERM", pid)
      Timeout.timeout(5) { Process.wait(pid) }

      expect($CHILD_STATUS.exitstatus).to eq(0)
    ensure
      begin
        Process.kill("KILL", pid) if pid && Process.waitpid(pid, Process::WNOHANG).nil?
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end
end
