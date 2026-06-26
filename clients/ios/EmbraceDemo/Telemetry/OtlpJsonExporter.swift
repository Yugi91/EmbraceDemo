import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

// Minimal OTLP/HTTP-JSON exporters for both demo arms.
//
// Ported (near-verbatim) from the Flutter iOS spike
// (clients/flutter/ios/Runner/OtlpJsonExporter.swift). EmbraceIO 6.20.0 pulls in
// OpenTelemetry-Swift-Sdk (the SpanExporter / LogRecordExporter protocols) but NOT
// an off-the-shelf OTLP-HTTP exporter pod — rather than add gRPC/protobuf pods that
// risk clashing with Embrace's pinned OTel version, we hand-roll a tiny exporter
// that POSTs OTLP/JSON straight to grafana/otel-lgtm.
//
// Same instance type is used in two places:
//   • handed to Embrace.Options(export: OpenTelemetryExport(...))  (Embrace arm)
//   • wired into a TracerProviderSdk / LoggerProviderSdk           (plain-OTel arm)
//
// Demo-grade: best-effort, fire-and-forget, no retry/backoff.

private let kTracesURL = URL(string: "http://localhost:4318/v1/traces")!
private let kLogsURL = URL(string: "http://localhost:4318/v1/logs")!

private func nanoString(_ d: Date) -> String {
  String(UInt64(d.timeIntervalSince1970 * 1_000_000_000))
}

private func anyValue(_ v: AttributeValue) -> [String: Any] {
  switch v {
  case let .string(s): return ["stringValue": s]
  case let .bool(b): return ["boolValue": b]
  case let .int(i): return ["intValue": String(i)]
  case let .double(d): return ["doubleValue": d]
  default: return ["stringValue": "\(v)"]
  }
}

private func kvList(_ attrs: [String: AttributeValue]) -> [[String: Any]] {
  attrs.map { ["key": $0.key, "value": anyValue($0.value)] }
}

private func post(_ url: URL, _ body: [String: Any]) {
  guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
  var req = URLRequest(url: url)
  req.httpMethod = "POST"
  req.setValue("application/json", forHTTPHeaderField: "Content-Type")
  req.httpBody = data
  URLSession.shared.dataTask(with: req).resume()
}

final class OtlpJsonSpanExporter: SpanExporter {
  func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    guard let first = spans.first else { return .success }
    let resourceAttrs = kvList(first.resource.attributes)

    let otlpSpans: [[String: Any]] = spans.map { s in
      // OTLP SpanKind: 0=UNSPECIFIED,1=INTERNAL,2=SERVER,3=CLIENT,...
      let kindCode: Int
      switch s.kind {
      case .internal: kindCode = 1
      case .server: kindCode = 2
      case .client: kindCode = 3
      case .producer: kindCode = 4
      case .consumer: kindCode = 5
      }
      // OTLP StatusCode: 0=UNSET,1=OK,2=ERROR.
      let statusCode: Int
      switch s.status {
      case .ok: statusCode = 1
      case .error: statusCode = 2
      case .unset: statusCode = 0
      }
      // Span events (timestamped) — workflow steps rely on these.
      let otlpEvents: [[String: Any]] = s.events.map { e in
        [
          "timeUnixNano": nanoString(e.timestamp),
          "name": e.name,
          "attributes": kvList(e.attributes),
        ]
      }
      var span: [String: Any] = [
        "traceId": s.traceId.hexString,
        "spanId": s.spanId.hexString,
        "name": s.name,
        "kind": kindCode,
        "startTimeUnixNano": nanoString(s.startTime),
        "endTimeUnixNano": nanoString(s.endTime),
        "attributes": kvList(s.attributes),
        "events": otlpEvents,
        "status": ["code": statusCode],
      ]
      if let parent = s.parentSpanId { span["parentSpanId"] = parent.hexString }
      return span
    }

    let payload: [String: Any] = [
      "resourceSpans": [[
        "resource": ["attributes": resourceAttrs],
        "scopeSpans": [["scope": ["name": "embrace-ios-otlp-json"],
                        "spans": otlpSpans]],
      ]],
    ]
    post(kTracesURL, payload)
    return .success
  }

  func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode { .success }
  func shutdown(explicitTimeout: TimeInterval?) {}
}

final class OtlpJsonLogExporter: LogRecordExporter {
  func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
    guard let first = logRecords.first else { return .success }
    let resourceAttrs = kvList(first.resource.attributes)

    let records: [[String: Any]] = logRecords.map { r in
      var rec: [String: Any] = [
        "timeUnixNano": nanoString(r.timestamp),
        "severityNumber": r.severity?.rawValue ?? 9,
        "severityText": r.severity.map { "\($0)" } ?? "INFO",
        "attributes": kvList(r.attributes),
      ]
      if let body = r.body { rec["body"] = ["stringValue": "\(body)"] }
      return rec
    }

    let payload: [String: Any] = [
      "resourceLogs": [[
        "resource": ["attributes": resourceAttrs],
        "scopeLogs": [["scope": ["name": "embrace-ios-otlp-json"],
                       "logRecords": records]],
      ]],
    ]
    post(kLogsURL, payload)
    return .success
  }

  func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult { .success }
  func shutdown(explicitTimeout: TimeInterval?) {}
}
