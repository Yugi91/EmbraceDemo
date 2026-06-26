# Telemetry Schema Contract

Every client (Web / Android / iOS / Flutter / plain-OTel) emits telemetry using these
**identical** attribute keys so a single Grafana dashboard works across all platforms.
Embrace SDK exports **traces + logs only — no metrics**; numeric values (RAM/storage/network)
ride as span/log attributes and are turned into metrics via the collector's spanmetrics connector.

## Resource / common attributes (on every span & log)
| Key | Type | Example | Source |
|---|---|---|---|
| `user.id` | string | `demo-user-001` | app (fixed demo user) |
| `device.model` | string | `iPhone15,2` / `Pixel 7` | SDK / platform API |
| `device.manufacturer` | string | `Apple` / `Google` | SDK / platform API |
| `app.version` | string | `1.0.0+1` | build config |
| `os.version` | string | `iOS 17.4` / `Android 14` | platform API |
| `service.name` | string | `embrace-demo-web` etc. | per client |
| `telemetry.tool` | string | `embrace` \| `otel` | which SDK arm produced it (for F1 compare) |

## Per-action attributes
| Key | Type | Notes |
|---|---|---|
| `action.name` | string | `delay` \| `crash` \| `anr` \| `workflow` \| `caught_error` |
| `system.free_ram_mb` | double | sampled at action start; native auto + set explicitly for parity |
| `system.free_storage_mb` | double | sampled at action start |
| `network.speed_mbps` | double | NOT auto-captured by Embrace → measured/estimated + set custom |
| `network.type` | string | `wifi` \| `cellular` \| `ethernet` \| `none` |

## Workflow span shape (capture → save → sync)
```
span: workflow                       (parent, action.name=workflow)
 ├─ event: started                   (timestamp)
 ├─ span: capture                    child — attrs: data (e.g. bytes), status=ok|failure
 │    └─ event: captured / failed
 ├─ span: save                       child — attrs: path, status
 │    └─ event: saved / failed
 └─ span: sync                       child — attrs: endpoint, http.status, status
      └─ event: synced / failed      on error: span status = ERROR, ErrorCode.FAILURE, exception attrs
```
Each child span carries: `step.name`, `step.status` (`ok|failure`), `step.data`, timestamped
events, and on error an `exception.type` / `exception.message` + span status = ERROR.

## Self-tracing loop guard
The OTLP export is itself a network call the SDK would auto-instrument → infinite loop.
Exclude the collector endpoint from network capture:
- Android: `disabled_url_patterns`
- Web: `network.ignoreUrls`
- iOS: ignored URLs in network config
