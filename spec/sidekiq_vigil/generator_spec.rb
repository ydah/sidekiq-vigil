# frozen_string_literal: true

require "tmpdir"
require "rbconfig"
require "generators/sidekiq_vigil/install_generator"

RSpec.describe SidekiqVigil::Generators::InstallGenerator do
  it "generates an initializer that loads in plain Ruby" do
    skip("fallback generator is only used without Rails") unless described_class.respond_to?(:install)

    Dir.mktmpdir do |directory|
      destination = File.join(directory, "config/initializers/sidekiq_vigil.rb")
      described_class.install(destination)

      expect(File.read(destination)).to include("SidekiqVigil.configure")
      command = [RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}", "-e", "load ARGV.fetch(0)", destination]
      expect(system(*command, out: File::NULL, err: File::NULL)).to be(true)
    end
  end
end
