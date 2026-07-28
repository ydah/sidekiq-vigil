# frozen_string_literal: true

RSpec.describe SidekiqVigil do
  it "has a version number" do
    expect(described_class::VERSION).to eq("0.1.0")
  end

  it "keeps the generated require path and namespace compatible" do
    require "sidekiq/vigil"

    expect(Sidekiq::Vigil).to equal(described_class)
  end

  it "validates the configuration after the block" do
    config = described_class.configure do |value|
      value.interval = 15
    end

    expect(config.interval).to eq(15)
  end
end
