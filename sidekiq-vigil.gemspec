# frozen_string_literal: true

require_relative "lib/sidekiq_vigil/version"

Gem::Specification.new do |spec|
  spec.name = "sidekiq-vigil"
  spec.version = SidekiqVigil::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Battery-included monitoring and alerting for Sidekiq"
  spec.description = "Monitors Sidekiq health with Redis-backed checks, alert lifecycles, and pluggable notifications."
  spec.homepage = "https://github.com/ydah/sidekiq-vigil"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        (f == "Appraisals") ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ gemfiles/ benchmark/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq", ">= 7.0"
end
