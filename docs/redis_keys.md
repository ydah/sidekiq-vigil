# Redis key contract

Every key is namespaced below `vigil:<key_prefix>:`. Storage writes require a positive TTL; the `alerts` hash is the only persistent exception and is explicitly pruned by `Alert::Manager`.

The first column of this table is contract-tested against `SidekiqVigil::Storage::KEY_CATALOG`.

| Key suffix | Type | Content | TTL | Owner |
|---|---|---|---|---|
| `stats:{yyyymmddHHMM}` | hash | Minute counters for processed/failed jobs and worker classes | 8 days | Reporter |
| `exec:{queue}` | hash | Execution count/sum/max by queue | 1 hour | Reporter |
| `alerts` | hash | Serialized alert lifecycle state | Explicitly managed; stale targets are pruned | Alert::Manager |
| `history:{alert_id}` | list | Latest 30 observed values for a single alert | 24 hours | Alert::Manager |
| `snapshot` | string | Timestamped check results and alert states | `interval × 4` | Checker |
| `leader` | string | Leader-election token | `interval × 3` | LeaderElection |
| `mem:{process_id}` | string | Reporter RSS in KiB | `flush_interval × 3` | Reporter |
| `config_digest` | hash | Configuration digest by process | 1 hour | Reporter |
| `mute` | string | Manual mute reason and expiration | Requested duration | Alert::Mute |
| `check_state:{check-specific-suffix}` | string | Growth, quiet-process, or sustained-condition state | Check-specific positive TTL | Checks |
