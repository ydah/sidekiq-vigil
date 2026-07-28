# frozen_string_literal: true

RSpec.describe Sidekiq::Vigil do
  it "has a version number" do
    expect(Sidekiq::Vigil::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(false).to eq(true)
  end
end
