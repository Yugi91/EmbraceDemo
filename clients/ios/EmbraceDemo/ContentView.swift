import SwiftUI

struct ContentView: View {
  let actions: DemoActions
  @State private var lastAction = "—"

  var body: some View {
    NavigationView {
      List {
        Section(header: Text("Status")) {
          row("telemetry.tool", actions.toolLabel)
          row("exporting", actions.isExporting ? "true" : "false")
          row("service.name", TelemetryConfig.serviceName)
          row("last action", lastAction)
        }
        Section(header: Text("Actions")) {
          button("delay", "Delay (perf span · B2)", background: true) { actions.delay() }
          button("crash", "Crash (unhandled · B1)", background: false) { actions.crash() }
          button("app-hang", "App Hang ~6s (E3)", background: false) { actions.appHang() }
          button("frames", "Frames / Jank (E4)", background: false) { actions.frames() }
          button("workflow", "Workflow (parent+children · B4)", background: true) {
            actions.workflow()
          }
          button("caught_error", "Caught Error (handled · E7)", background: true) {
            actions.caughtError()
          }
          button("network", "Network (real GET · L2)", background: true) { actions.network() }
          button("oom", "OOM (allocate · L3)", background: true) { actions.oom() }
}
        Section(header: Text("Note")) {
          Text(
            "Embrace arm reports under the bundle-id service.name and drops contract attrs; "
              + "the OTel arm honors service.name=embrace-demo-ios exactly.")
            .font(.footnote).foregroundColor(.secondary)
        }
      }
      .navigationBarTitle("Embrace Demo iOS", displayMode: .inline)
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private func row(_ k: String, _ v: String) -> some View {
    HStack {
      Text(k).foregroundColor(.secondary)
      Spacer()
      Text(v).font(.system(.body, design: .monospaced))
    }
  }

  /// `background: true` runs the action off the main thread (keeps UI responsive).
  /// `background: false` runs it on the main thread — required for crash/hang/frames
  /// whose whole purpose is to affect the main thread / process.
  private func button(_ id: String, _ label: String, background: Bool, _ run: @escaping () -> Void)
    -> some View
  {
    Button(label) {
      lastAction = id
      if background {
        DispatchQueue.global(qos: .userInitiated).async(execute: run)
      } else {
        DispatchQueue.main.async(execute: run)
      }
    }
  }
}
