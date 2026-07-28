# Sidekiq Vigil

Sidekiq Vigil is battery-included monitoring and alerting for Sidekiq. It runs against the Redis you already use, evaluates twelve health checks, keeps an alert lifecycle across restarts, and sends firing, ongoing, and recovery notifications.

[![CI](https://github.com/ydah/sidekiq-vigil/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/sidekiq-vigil/actions/workflows/main.yml)

## Requirements

- Ruby 3.2 or newer
- Sidekiq 7.x or 8.x
- Redis 7 or a Sidekiq-compatible Redis implementation

Sidekiq is the only runtime dependency.

## Five-minute quick start

Add the gem from Git until the first RubyGems release:

```ruby
gem "sidekiq-vigil", github: "ydah/sidekiq-vigil"
```

Generate an initializer in Rails:

```sh
bundle install
bundle exec rails generate sidekiq_vigil:install
```

Or create a pure Ruby initializer:

```ruby
require "sidekiq_vigil"

SidekiqVigil.configure do |config|
  config.key_prefix = "myapp"
  config.redis = { url: ENV["REDIS_URL"] }

  config.notifier :slack,
    webhook_url: ENV["SLACK_WEBHOOK_DEFAULT"],
    routes: { critical: ENV["SLACK_WEBHOOK_INCIDENTS"] }.compact,
    mention: { critical: "<!here>" },
    web_ui_url: "https://example.com/sidekiq"
  config.notifier :log

  config.check :queue_latency, warn: 60, critical: 300
  config.check :queue_size, warn: 1_000, critical: 10_000
end
```

Start Sidekiq normally. The server middleware, Reporter, and leader-elected Checker are installed automatically. Outside `production`, external notification is disabled unless `config.enabled = true` is assigned explicitly; Log remains available.

Test every configured notifier before relying on it:

```sh
bundle exec vigil --config config/sidekiq_vigil.rb test-notify
```

## Recommended production topology

Use Embedded mode for collection and checks, expose `SidekiqVigil::HealthApp`, and have an external uptime monitor call `/healthz`. Embedded monitoring cannot run when every Sidekiq process is dead; the endpoint detects that condition because an expired snapshot returns 503.

```ruby
# config.ru
require "sidekiq_vigil"

storage = SidekiqVigil.build_storage
health = SidekiqVigil::HealthApp.new(
  storage: storage,
  interval: SidekiqVigil.config.interval
)

# Authentication is intentionally supplied by the application.
use Rack::Auth::Basic do |username, password|
  Rack::Utils.secure_compare(username, ENV.fetch("VIGIL_HEALTH_USER")) &&
    Rack::Utils.secure_compare(password, ENV.fetch("VIGIL_HEALTH_PASSWORD"))
end
run health
```

`GET /healthz` returns 200 only when every result is OK and the snapshot is at most `interval × 2` old. `GET /status.json` includes check results, freshness, and age. Both return 503 when unhealthy or unavailable.

## Execution modes

| Mode | Command/integration | Collection | Detects total Sidekiq outage |
|---|---|---:|---:|
| Embedded (default) | Require the gem in Sidekiq | Reporter + leader Checker | Through stale external `/healthz` probe |
| Standalone | `vigil --config config/vigil.rb` | Checker only | Yes |
| Oneshot | `vigil --config config/vigil.rb check --once` | One Checker cycle | Yes, when scheduled externally |

Standalone configuration is plain Ruby and must not depend on Rails constants.

```sh
bundle exec vigil --config config/vigil.rb status
bundle exec vigil --config config/vigil.rb mute 30m --reason "database maintenance"
bundle exec vigil --config config/vigil.rb unmute
```

`TERM` and `INT` stop Standalone mode gracefully and release its leader lock.

## Check catalog

| Check | Default behavior | Important options |
|---|---|---|
| `queue_latency` | Warn 60s, critical 300s | `queues`, `per_queue` |
| `queue_size` | Warn 1,000, critical 10,000 | `queues`, `per_queue` |
| `retry_set` | Warn 100, critical 1,000 | `growth_only` |
| `dead_set` | Warn 1, critical 50 | `growth_only` |
| `process_alive` | Require at least one active process | `min_processes`, `quiet_threshold` |
| `utilization` | Warn 85%, critical 95% after 300s | `sustained` |
| `failure_rate` | Warn 5%, critical 20%, minimum 20 attempts | `window`, `min_samples` |
| `stuck_jobs` | Critical after 30 minutes | `threshold` |
| `memory` | Warn 1,500 MiB, critical 2,500 MiB | `warn_mb`, `critical_mb` |
| `redis_health` | PING latency and maxmemory usage | `latency_ms`, `memory_pct` |
| `scheduled_backlog` | Warn on jobs overdue by five minutes | `overdue` |
| `throughput_anomaly` | Disabled by default | `drop_pct`, `baseline_days`, `min_samples` |

All checks use Sidekiq's public `sidekiq/api` objects. A check exception becomes an `error` result; it does not terminate Sidekiq or the Checker loop. Custom checks subclass `SidekiqVigil::Check::Base` and return one `SidekiqVigil::Result` or an array.

Failure rate counts execution attempts, so a job that fails and retries can contribute more than one failure. Stuck-job duration assumes synchronized host clocks (NTP).

## Full configuration reference

```ruby
SidekiqVigil.configure do |config|
  config.enabled = true
  config.interval = 30
  config.flush_interval = 10
  config.key_prefix = "myapp"
  config.timezone = "Asia/Tokyo"
  config.redis = {
    url: ENV["REDIS_URL"],
    pool_size: 5,
    pool_timeout: 1
  }

  config.notifier :slack,
    webhook_url: ENV["SLACK_WEBHOOK_DEFAULT"],
    routes: { critical: ENV["SLACK_WEBHOOK_INCIDENTS"] },
    mention: { critical: "<!subteam^S012345>" },
    web_ui_url: "https://example.com/sidekiq"
  config.notifier :webhook, url: "https://events.example.com/sidekiq"
  config.notifier :log

  config.alerting do |alerting|
    alerting.pending_cycles = 2
    alerting.cooldown = 600
    alerting.resolve_notice = true
    alerting.flap_window = 120
    alerting.flap_threshold = 4
    alerting.escalate_after = 3
    alerting.group_threshold = 5
    alerting.group_top_n = 5
    alerting.mutes = [
      { cron: "0 3 * * 0", duration: 3_600, reason: "weekly maintenance" }
    ]
  end
end
```

Slack Incoming Webhooks have a fixed channel. Severity routing therefore selects different URLs; Sidekiq Vigil does not attempt to override `channel` in a payload. Mentions must use `<@U…>`, `<!subteam^S…>`, or `<!here>` syntax. Plain text such as `@oncall` fails configuration validation. Secret URLs are filtered from notifier inspection and error logging.

The generic webhook contract and examples are documented in [docs/webhook_schema.md](docs/webhook_schema.md).

## Alert lifecycle

Each `check_name + target` moves through `OK → PENDING → FIRING → RESOLVED → OK`. State survives leader changes and process restarts.

- `pending_cycles` removes single-cycle noise.
- `cooldown` controls ongoing notifications.
- `escalate_after` upgrades sustained warnings to critical.
- `flap_threshold` transitions inside `flap_window` emit one flapping event and hold refiring until the window closes.
- history retains the latest 30 values for 24 hours.
- targets that disappear are pruned every cycle.
- more than `group_threshold` events in one cycle become one digest with severity counts and `group_top_n` details.
- mute windows continue state transitions but suppress delivery; unmute reports current firing state once.

All Redis keys start with `vigil:<key_prefix>:`. The Storage API rejects non-positive or missing TTLs except for the explicitly managed `alerts` hash. The complete, contract-tested key list is in [docs/redis_keys.md](docs/redis_keys.md).

## Existing tools

| Tool | Primary purpose | Built-in lifecycle/notifications | Additional stack |
|---|---|---:|---:|
| yabeda-sidekiq / Prometheus exporters | Metrics export | No | Prometheus/Grafana/Alertmanager |
| Sidekiq Alive | Kubernetes liveness | No | External probe |
| sidekiq-job_alert | Queue/dead Slack alerts | Limited | No |
| Sidekiq Web metrics | Execution exploration | No | No |
| Sidekiq Vigil | Checks, lifecycle, mute/group/recovery | Yes | No |

## Known limitations

- During complete Redis failure, each process loses leader coordination and direct `redis_health` notifications can be duplicated. Recovery may also cause another notification. Use an external `/healthz` probe as the primary total-outage signal.
- Throughput anomaly baseline uses the previous seven same-time windows and does not model weekday/weekend seasonality. It is opt-in and has a minimum-sample guard.
- Stuck-job detection compares timestamps from different hosts and requires synchronized clocks.
- RSS collection supports Linux `/proc` and macOS `ps`; the memory check is skipped on Windows.
- Sidekiq Pro and Enterprise use only the same public APIs, but the combinations are not yet separately certified.
- Slack Bot Token mode, thread tracking, weekday baselines, and Prometheus output are planned after v1.

## Development

```sh
bundle install
redis-server --port 16379 --save "" --appendonly no
VIGIL_REDIS_URL=redis://127.0.0.1:16379/15 bundle exec rake
bundle exec appraisal sidekiq_7 rspec
bundle exec appraisal sidekiq_8 rspec
bundle exec ruby benchmark/middleware_overhead.rb
bundle exec rake build
```

The benchmark compares middleware-on and middleware-off in the same process, writes a JSON artifact, and only warns when the relative run has unusually high overhead.

## FAQ

**Does the middleware call Redis for every job?**

No. It updates a mutex-protected in-process counter. Reporter flushes aggregates in a Redis pipeline.

**Can I run Embedded and Standalone together?**

Yes. The Redis leader lock prevents duplicate normal checks. A configuration digest warning appears when process configurations differ.

**Why did Slack not receive a development notification?**

External notifiers are safe by default outside production. Explicitly assign `config.enabled = true`, then run `vigil test-notify`.

**Can I keep using yabeda or an APM?**

Yes. Sidekiq Vigil does not replace or modify Sidekiq's metrics subsystem.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
