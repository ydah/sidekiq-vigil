# Webhook payload schema

The generic webhook notifier sends one JSON object per alert event. The normative JSON Schema is [`webhook_event.schema.json`](webhook_event.schema.json).

## Compatibility

- `schema_version` is currently `1.0`.
- New optional properties may be added in a minor release.
- Removing a property, changing its type, or changing event semantics requires a schema major-version change.
- Receivers should ignore unknown optional properties.

## Regular event

```json
{
  "schema_version": "1.0",
  "event": "firing",
  "alert_id": "queue_size:critical",
  "timestamp": "2026-07-28T12:00:00Z",
  "alert": {
    "check_name": "queue_size",
    "target": "critical",
    "severity": "critical",
    "value": 250,
    "threshold": 200,
    "message": "250 jobs waiting",
    "metadata": {}
  },
  "state": {
    "status": "firing",
    "cycles": 2,
    "first_seen_at": 1785239970.0,
    "last_notified_at": 1785240000.0,
    "last_transition_at": 1785240000.0,
    "severity": "critical",
    "value": 250,
    "threshold": 200,
    "message": "250 jobs waiting",
    "suppressed": false,
    "flap_notified": false
  },
  "history": [
    { "timestamp": 1785239970.0, "value": 190, "severity": "warn" },
    { "timestamp": 1785240000.0, "value": 250, "severity": "critical" }
  ]
}
```

## Digest event

A digest replaces individual notifications when the number of events in one checker cycle is greater than `group_threshold`. It contains severity counts and the highest-severity alerts.

```json
{
  "schema_version": "1.0",
  "event": "digest",
  "alert_id": "digest",
  "timestamp": "2026-07-28T12:00:00Z",
  "counts": { "critical": 3, "warn": 4 },
  "alerts": []
}
```
