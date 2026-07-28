# frozen_string_literal: true

require "sidekiq_vigil"

class VigilE2EJob
  include Sidekiq::Job

  sidekiq_options retry: false

  def perform(mode = nil)
    raise "injected failure" if mode == "fail"
  end
end

SidekiqVigil.configure do |config|
  config.enabled = true
  config.interval = 1
  config.flush_interval = 1
  config.key_prefix = "e2e"
  config.redis = { url: ENV.fetch("VIGIL_REDIS_URL") }
  config.checks.clear
  config.check :queue_size,
               queues: %w[vigil_e2e_a vigil_e2e_b vigil_e2e_c],
               warn: 1,
               critical: 1
  config.check :queue_latency,
               queues: %w[vigil_e2e_a],
               warn: 1,
               critical: 1
  config.check :failure_rate, warn: 0.5, critical: 0.9, window: 60, min_samples: 1
  config.notifier :slack, webhook_url: ENV.fetch("MOCK_SLACK_URL"), retries: 0
  config.alerting do |alerting|
    alerting.pending_cycles = 1
    alerting.cooldown = 60
    alerting.group_threshold = 2
  end
end
