import Foundation

/// The demo actions, each emitting telemetry per SCHEMA_CONTRACT. Pure logic — no
/// SwiftUI imports — so the UI stays a thin shell. Mirrors the Flutter
/// `demo_actions.dart` semantics, plus a `frames` (jank) action for E4.
final class DemoActions {
  private let t: TelemetryService
  /// Retained allocations for the `oom` action — grows unbounded until the OS kills us.
  private var blocks: [[UInt8]] = []
  init(_ t: TelemetryService) { self.t = t }

  /// Attach the per-action `system.*` / `network.*` sample to a span.
  private func attachSystemSample(_ span: TelemetrySpan) {
    let s = SystemSample.take()
    span.setAttribute(Attr.freeRamMb, String(s.freeRamMb))
    span.setAttribute(Attr.freeStorageMb, String(s.freeStorageMb))
    span.setAttribute(Attr.networkSpeedMbps, String(s.networkSpeedMbps))
    span.setAttribute(Attr.networkType, s.networkType)
  }

  /// ACTION — `metric`: a CONCURRENT + nested perf span tree (B2 perf span).
  ///
  ///   metric            (root)
  ///   ├── A             (child of metric — own queue, parallel with B)
  ///   │   ├── C         (child of A — sequential, first)
  ///   │   └── D         (child of A — sequential, after C)
  ///   └── B             (child of metric — parallel with A)
  ///
  /// A and B run on separate global-queue blocks via a DispatchGroup (real parallelism);
  /// C then D run sequentially inside A's block. Each leaf brackets a `Thread.sleep` with
  /// its own child span so the captured durations are real. Children pass `parent:`
  /// EXACTLY like `workflow()` does, so the tree nests in both the Embrace and OTel arms.
  func metric() {
    t.addBreadcrumb("tapped: metric")
    let metric = t.startSpan("metric", actionName: "metric")
    attachSystemSample(metric)
    metric.addEvent("metric.start")

    let group = DispatchGroup()

    // Branch A (parent=metric): runs on its own queue, in parallel with B. Inside,
    // C then D run sequentially, each a child of A.
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      let a = self.t.startSpan("A", parent: metric)
      a.setAttribute(Attr.actionName, "metric")
      a.setAttribute("task.name", "A")
      a.addEvent("A.start")

      // C — child of A, sequential (first).
      let c = self.t.startSpan("C", parent: a)
      let cStart = Date()
      c.setAttribute(Attr.actionName, "metric")
      c.setAttribute("task.name", "C")
      Thread.sleep(forTimeInterval: 0.12)
      c.setAttribute("work.ms", String(Int(Date().timeIntervalSince(cStart) * 1000)))
      c.end()

      // D — child of A, sequential (after C).
      let d = self.t.startSpan("D", parent: a)
      let dStart = Date()
      d.setAttribute(Attr.actionName, "metric")
      d.setAttribute("task.name", "D")
      Thread.sleep(forTimeInterval: 0.09)
      d.setAttribute("work.ms", String(Int(Date().timeIntervalSince(dStart) * 1000)))
      d.end()

      a.addEvent("A.end")
      a.end()
      group.leave()
    }

    // Branch B (parent=metric): runs in parallel with A on another queue.
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      let b = self.t.startSpan("B", parent: metric)
      let bStart = Date()
      b.setAttribute(Attr.actionName, "metric")
      b.setAttribute("task.name", "B")
      b.addEvent("B.start")
      Thread.sleep(forTimeInterval: 0.15)
      b.setAttribute("work.ms", String(Int(Date().timeIntervalSince(bStart) * 1000)))
      b.addEvent("B.end")
      b.end()
      group.leave()
    }

    // Join A and B, then close the root span (its duration ≈ max(A, B)).
    group.wait()
    metric.addEvent("metric.end")
    metric.end()
    t.log("metric perf tree done (A‖B, A→C→D)")
  }

  /// ACTION — `crash`: an UNHANDLED native error (B1). A force-unwrap of nil ->
  /// SIGABRT/fatalError, caught by Embrace's KSCrash handler (uploaded next launch).
  func crash() {
    t.addBreadcrumb("tapped: crash")
    t.log(
      "about to crash (unhandled)", severity: .warning,
      attributes: [Attr.actionName: "crash"])
    t.flush()  // give the exporter a chance before the process dies
    // True unhandled crash: force-unwrap nil. Embrace/KSCrash captures the signal.
    let nilValue: Int? = nil
    _ = nilValue!
  }

  /// ACTION — `anr` / app-hang: block the MAIN thread ~6s (iOS equivalent of ANR, E3).
  /// Must be called on the main thread to actually freeze the UI.
  func appHang() {
    t.addBreadcrumb("tapped: anr")
    let span = t.startSpan("anr", actionName: "anr")
    attachSystemSample(span)
    span.addEvent("anr.block.start")
    // Synchronous busy-wait blocks the main thread -> app hang.
    let stop = Date().addingTimeInterval(6.0)
    var x = 0.0
    while Date() < stop {
      x += (Double.random(in: 0..<1_000_000)).squareRoot()
    }
    span.setAttribute("anr.block_ms", "6000")
    span.setAttribute("anr.sink", String(format: "%.0f", x))
    span.addEvent("anr.block.end")
    span.end()
    t.log("anr block released (6s)")
  }

  /// ACTION — `frames` / jank (E4): a sequence of main-thread micro-stalls that drop
  /// frames without a single long hang. Each stall is ~120ms (≈7 dropped frames at
  /// 60fps) — "slow frames" territory, repeated to provoke any slow/frozen-frames
  /// instrumentation. Must run on the main thread.
  func frames() {
    t.addBreadcrumb("tapped: frames")
    let span = t.startSpan("frames", actionName: "frames")
    attachSystemSample(span)
    span.addEvent("frames.jank.start")
    let stalls = 12
    let stallMs = 120
    for i in 0..<stalls {
      let stop = Date().addingTimeInterval(Double(stallMs) / 1000.0)
      var x = 0.0
      while Date() < stop { x += Double(i) * 1.0001 }
      // Yield briefly so the run loop ticks between stalls (renders a frame).
      RunLoop.current.run(until: Date().addingTimeInterval(0.016))
      _ = x
    }
    span.setAttribute("frames.stall_count", String(stalls))
    span.setAttribute("frames.stall_ms", String(stallMs))
    span.addEvent("frames.jank.end")
    span.end()
    t.log("frames jank burst done (\(stalls)x\(stallMs)ms)")
  }

  /// ACTION — `workflow`: parent span + capture->save->sync child spans with
  /// timestamped events. `sync` randomly fails -> child span ERROR + exception attrs
  /// (B4 custom-event shape, per SCHEMA_CONTRACT workflow diagram).
  func workflow() {
    t.addBreadcrumb("tapped: workflow")
    let parent = t.startSpan("workflow", actionName: "workflow")
    attachSystemSample(parent)
    parent.addEvent("started")

    // capture
    let capture = t.startSpan("capture", parent: parent)
    let bytes = 1024 + Int.random(in: 0..<4096)
    capture.setAttribute(Attr.stepName, "capture")
    capture.setAttribute(Attr.stepStatus, "ok")
    capture.setAttribute(Attr.stepData, String(bytes))
    capture.addEvent("captured", attributes: ["bytes": String(bytes)])
    capture.end()

    // save
    let save = t.startSpan("save", parent: parent)
    let path = "/tmp/demo/capture.bin"
    save.setAttribute(Attr.stepName, "save")
    save.setAttribute(Attr.stepStatus, "ok")
    save.setAttribute(Attr.stepData, path)
    save.addEvent("saved", attributes: ["path": path])
    save.end()

    // sync — sometimes fails (~50%)
    let sync = t.startSpan("sync", parent: parent)
    let endpoint = "https://api.example.test/sync"
    sync.setAttribute(Attr.stepName, "sync")
    sync.setAttribute("endpoint", endpoint)
    if Bool.random() {
      sync.setAttribute("http.status", "503")
      sync.setAttribute(Attr.stepStatus, "failure")
      let err = DemoSyncError.http(503, endpoint)
      sync.addEvent("failed", attributes: ["http.status": "503"])
      sync.recordError(err)
      sync.end(errored: true)
      parent.addEvent("sync_failed")
      parent.end(errored: true)
      t.log("workflow failed at sync (HTTP 503)", severity: .error)
    } else {
      sync.setAttribute("http.status", "200")
      sync.setAttribute(Attr.stepStatus, "ok")
      sync.addEvent("synced", attributes: ["http.status": "200"])
      sync.end()
      parent.addEvent("completed")
      parent.end()
      t.log("workflow completed ok")
    }
  }

  /// ACTION — `caught_error`: a handled exception (E7 feed). try/catch then report.
  func caughtError() {
    t.addBreadcrumb("tapped: caught_error")
    do {
      throw DemoHandledError.demo("demo handled exception (action.name=caught_error)")
    } catch {
      t.recordCaughtError(error)
      t.log(
        "caught & reported handled error", severity: .warning,
        attributes: [Attr.actionName: "caught_error"])
    }
  }

  /// ACTION — `network` (LEVEL 2): a REAL HTTP GET wrapped in a span. The Embrace iOS
  /// SDK auto-captures URLSession requests, so this external call also surfaces in
  /// Embrace's Network view under the jsonplaceholder.typicode.com domain. (The local
  /// OTLP collector URL is excluded by the self-tracing guard in the Embrace arm, so
  /// only genuine app traffic like this is captured.)
  func network() {
    t.addBreadcrumb("tapped: network")
    let span = t.startSpan("network", actionName: "network")
    attachSystemSample(span)
    let urlString = "https://jsonplaceholder.typicode.com/todos/1"
    span.setAttribute("http.url", urlString)
    span.setAttribute("http.method", "GET")
    span.addEvent("network.request.start")

    // Synchronous wait so the span brackets the real request (this action runs off the
    // main thread, like the other background actions).
    let sem = DispatchSemaphore(value: 0)
    var statusCode: Int?
    var requestError: Error?
    let task = URLSession.shared.dataTask(with: URL(string: urlString)!) { _, response, error in
      statusCode = (response as? HTTPURLResponse)?.statusCode
      requestError = error
      sem.signal()
    }
    task.resume()
    sem.wait()

    if let error = requestError {
      span.recordError(error)
      span.addEvent("network.request.failed")
      span.end(errored: true)
      t.log("network failed: \(error)", severity: .error, attributes: [Attr.actionName: "network"])
    } else {
      let code = statusCode ?? 0
      span.setAttribute("http.status_code", String(code))
      span.addEvent("network.request.end", attributes: ["http.status_code": String(code)])
      span.end()
      t.log("network completed (HTTP \(code))")
    }
  }

  /// ACTION — `oom` (LEVEL 3): allocate memory in an unbounded loop until the OS
  /// memory-kills the process. Each iteration retains another large block, so the
  /// footprint only grows. This WILL terminate the app (intended).
  func oom() {
    t.addBreadcrumb("tapped: oom")
    t.log("oom: allocating until killed", severity: .warning, attributes: [Attr.actionName: "oom"])
    t.flush()  // give the exporter a chance before the process is killed
    while true {
      // Retain a fresh 8 MiB block each pass; references are never released.
      blocks.append([UInt8](repeating: 0, count: 8 * 1024 * 1024))
      Thread.sleep(forTimeInterval: 0.02)
    }
  }

  /// Best-effort flush (used by the headless verifier before idle).
  func flush() { t.flush() }

  var toolLabel: String { t.tool }
  var isExporting: Bool { t.isExporting }
}

enum DemoSyncError: Error, CustomStringConvertible {
  case http(Int, String)
  var description: String {
    switch self {
    case let .http(code, endpoint): return "sync failed: HTTP \(code) from \(endpoint)"
    }
  }
}

enum DemoHandledError: Error, CustomStringConvertible {
  case demo(String)
  var description: String {
    switch self {
    case let .demo(msg): return msg
    }
  }
}
