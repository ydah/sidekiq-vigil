# frozen_string_literal: true

RSpec.describe "results and checks" do
  it "exposes an immutable serializable result" do
    result = SidekiqVigil::Result.new(check_name: :queue_size, target: "default", severity: :warn, value: 12)

    expect(result.alert_id).to eq("queue_size:default")
    expect(result.to_h).to include(check_name: "queue_size", severity: :warn)
    expect(result).to be_frozen
  end

  it "rejects unsupported severities" do
    expect do
      SidekiqVigil::Result.new(check_name: :x, severity: :notice)
    end.to raise_error(ArgumentError, /unknown severity/)
  end

  it "normalizes a custom check result to an array" do
    klass = Class.new(SidekiqVigil::Check::Base) do
      def call
        SidekiqVigil::Result.new(check_name:, severity: :ok)
      end
    end

    expect(klass.new(storage: nil).execute.first).to be_ok
  end

  it "converts check failures into error results" do
    logger = instance_double(Logger, error: nil)
    klass = Class.new(SidekiqVigil::Check::Base) do
      def call
        raise "boom"
      end
    end
    stub_const("ExplodingCheck", klass)

    result = klass.new(storage: nil, logger:).execute.first

    expect(result.severity).to eq(:error)
    expect(result.message).to include("RuntimeError: boom")
  end
end
