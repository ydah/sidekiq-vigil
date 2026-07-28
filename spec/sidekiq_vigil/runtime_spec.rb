# frozen_string_literal: true

RSpec.describe SidekiqVigil::Runtime do
  let(:config) { SidekiqVigil::Config.new }
  let(:reporter) { instance_double(SidekiqVigil::Reporter, start: true, stop: true) }
  let(:checker) { instance_double(SidekiqVigil::Checker, start: true, stop: true) }
  subject(:runtime) do
    described_class.new(config:, storage: nil, reporter:, checker:)
  end

  it "starts both embedded components and stops them safely" do
    expect(runtime.start).to be(true)
    runtime.stop

    expect(reporter).to have_received(:start)
    expect(checker).to have_received(:start)
    expect(checker).to have_received(:stop)
    expect(reporter).to have_received(:stop)
  end

  it "stops only the checker when Sidekiq becomes quiet" do
    runtime.quiet

    expect(checker).to have_received(:stop)
    expect(reporter).not_to have_received(:stop)
  end

  it "does not start when explicitly disabled" do
    config.enabled = false

    expect(runtime.start).to be(false)
    expect(reporter).not_to have_received(:start)
  end

  it "contains startup failures" do
    allow(reporter).to receive(:start).and_raise("boom")
    allow(SidekiqVigil.logger).to receive(:error)

    expect(runtime.start).to be(false)
  end
end
