# frozen_string_literal: true

require_relative "../../sidekiq_vigil/version"

module Sidekiq
  Vigil = SidekiqVigil unless const_defined?(:Vigil)
end
