import { Component, NgZone, OnInit, signal } from '@angular/core';
import { TelemetryService } from './telemetry/telemetry.service';

interface LogLine {
  ts: string;
  text: string;
}

@Component({
  selector: 'app-root',
  imports: [],
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App implements OnInit {
  protected readonly title = signal('embrace-demo-web');
  protected readonly tool = signal('');
  protected readonly ready = signal(false);
  protected readonly initError = signal('');
  protected readonly busy = signal(false);
  protected readonly logLines = signal<LogLine[]>([]);

  constructor(
    private readonly telemetry: TelemetryService,
    private readonly zone: NgZone
  ) {}

  ngOnInit(): void {
    this.tool.set(this.telemetry.tool);
    this.ready.set(this.telemetry.ready);
    this.initError.set(this.telemetry.initError ? String(this.telemetry.initError) : '');
    this.log(
      `Telemetry arm = "${this.telemetry.tool}", ready = ${this.telemetry.ready}` +
        (this.telemetry.initError ? `, initError = ${this.telemetry.initError}` : '')
    );
    this.telemetry.breadcrumb('app:loaded');

    // Headless-verifier hooks: deterministic, awaitable entry points.
    const w = window as unknown as Record<string, unknown>;
    w['__demo'] = {
      metric: () => this.runMetric(),
      caughtError: () => this.runCaughtError(),
      workflowOk: () => this.runWorkflow(false),
      workflowFail: () => this.runWorkflow(true),
      customEvent: () => this.runCustomEvent(),
      network: () => this.runNetwork(),
      oom: () => this.runOom(),
      crash: () => this.telemetry.triggerCrash(),
      flush: () => this.telemetry.flush(),
      ready: () => this.telemetry.ready,
      tool: () => this.telemetry.tool,
    };
  }

  private log(text: string): void {
    this.zone.run(() => {
      this.logLines.update((lines) =>
        [...lines, { ts: new Date().toISOString().slice(11, 23), text }].slice(-30)
      );
    });
  }

  async runMetric(): Promise<void> {
    this.busy.set(true);
    this.log('metric: building perf span tree (A‖B, A→C→D)...');
    try {
      await this.telemetry.metric();
      this.log('metric: span tree ended OK (root ≈ max(A, B))');
    } finally {
      this.busy.set(false);
    }
  }

  runCrash(): void {
    this.log('crash: throwing UNHANDLED error (B1)...');
    this.telemetry.triggerCrash();
  }

  async runCaughtError(): Promise<void> {
    this.busy.set(true);
    this.log('caught_error: throwing then logging handled exception (E7)...');
    try {
      await this.telemetry.caughtError();
      this.log('caught_error: handled + logged via logException(handled:true)');
    } finally {
      this.busy.set(false);
    }
  }

  async runWorkflow(forceFail?: boolean): Promise<void> {
    this.busy.set(true);
    this.log('workflow: parent span + capture/save/sync children...');
    try {
      const { syncFailed } = await this.telemetry.workflow(forceFail);
      this.log(`workflow: done, sync ${syncFailed ? 'FAILED (span status ERROR)' : 'OK'}`);
    } finally {
      this.busy.set(false);
    }
  }

  async runNetwork(): Promise<void> {
    this.busy.set(true);
    this.log('network: real fetch GET jsonplaceholder.typicode.com/todos/1 (L2)...');
    try {
      const { ok, status } = await this.telemetry.network();
      this.log(`network: ${ok ? 'OK' : 'FAILED'} (HTTP ${status}) — see Embrace Network view`);
    } finally {
      this.busy.set(false);
    }
  }

  async runOom(): Promise<void> {
    this.busy.set(true);
    this.log('oom: allocating large typed arrays — memory pressure, NOT an OS OOM-kill (L3)...');
    try {
      const { iterations, allocatedMb } = await this.telemetry.oom();
      this.log(`oom: allocated ~${allocatedMb} MB over ${iterations} iterations (browser has no OS OOM-kill)`);
    } finally {
      this.busy.set(false);
    }
  }

  runCustomEvent(): void {
    this.telemetry.customEvent('demo.custom_event', { 'event.source': 'button' });
    this.log('custom event emitted (B4)');
  }
}
