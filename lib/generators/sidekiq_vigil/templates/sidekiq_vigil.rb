# frozen_string_literal: true

require "sidekiq_vigil"

SidekiqVigil.configure do |config|
  # Monitoring is enabled by default. External notification is enabled by
  # default only in production; set this explicitly to opt in elsewhere.
  config.enabled = ENV.fetch("VIGIL_ENABLED") == "true" if ENV.key?("VIGIL_ENABLED")
  config.interval = Integer(ENV.fetch("VIGIL_INTERVAL", "30"))
  config.flush_interval = Integer(ENV.fetch("VIGIL_FLUSH_INTERVAL", "10"))
  config.key_prefix = ENV.fetch("VIGIL_KEY_PREFIX", "myapp")
  config.timezone = ENV.fetch("VIGIL_TIMEZONE", "UTC")
  redis_url = ENV.fetch("REDIS_URL", nil)
  config.redis = { url: redis_url } if redis_url

  config.check :queue_latency, warn: 60, critical: 300
  config.check :queue_size, warn: 1_000, critical: 10_000
  config.check :retry_set, warn: 100, critical: 1_000
  config.check :dead_set, warn: 1, critical: 50, growth_only: true
  config.check :process_alive, min_processes: 1
  config.check :utilization, warn: 0.85, critical: 0.95, sustained: 300
  config.check :failure_rate, warn: 0.05, critical: 0.20, window: 300, min_samples: 20
  config.check :stuck_jobs, threshold: 1_800
  config.check :memory, warn_mb: 1_500, critical_mb: 2_500
  config.check :redis_health, latency_ms: 100, memory_pct: 0.9
  config.check :scheduled_backlog, overdue: 300
  # Opt in after enough history has accumulated:
  # config.check :throughput_anomaly, drop_pct: 0.5, baseline_days: 7

  slack_webhook = ENV.fetch("SLACK_WEBHOOK_DEFAULT", nil)
  if slack_webhook
    config.notifier :slack,
                    webhook_url: slack_webhook,
                    routes: { critical: ENV.fetch("SLACK_WEBHOOK_INCIDENTS", nil) }.compact,
                    mention: { critical: ENV.fetch("SLACK_CRITICAL_MENTION", nil) }.compact,
                    web_ui_url: ENV.fetch("SIDEKIQ_WEB_UI_URL", nil)
  end
  config.notifier :log

  config.alerting do |alerting|
    alerting.pending_cycles = 2
    alerting.cooldown = 600
    alerting.resolve_notice = true
    alerting.flap_window = 120
    alerting.flap_threshold = 4
    alerting.group_threshold = 5
    alerting.group_top_n = 5
  end
end
