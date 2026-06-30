/**
 * Telemetry schema contract — see docs/SCHEMA_CONTRACT.md.
 * Every span & log emitted by either arm (Embrace or plain OTel) MUST carry these
 * exact attribute keys so a single Grafana dashboard works across all platforms.
 */
import type { Attributes } from '@opentelemetry/api';

/** Service name for this client (resource attribute). */
export const SERVICE_NAME = 'embrace-demo-web';

/** Build/demo constants. */
export const APP_VERSION = '1.0.0+1';
export const DEMO_USER_ID = 'demo-user-001';

/** OTLP collector endpoints (self-hosted grafana/otel-lgtm). */
export const OTLP_BASE = 'http://localhost:4318';
export const OTLP_TRACES_URL = `${OTLP_BASE}/v1/traces`;
export const OTLP_LOGS_URL = `${OTLP_BASE}/v1/logs`;

/** Which SDK arm produced the telemetry (F1 comparison). */
export type TelemetryTool = 'embrace' | 'otel';

/** Action names (must match the contract enum). */
export type ActionName = 'delay' | 'crash' | 'workflow' | 'caught_error' | 'network' | 'oom';

/** Schema attribute keys. */
export const ATTR = {
  USER_ID: 'user.id',
  DEVICE_MODEL: 'device.model',
  DEVICE_MANUFACTURER: 'device.manufacturer',
  APP_VERSION: 'app.version',
  OS_VERSION: 'os.version',
  SERVICE_NAME: 'service.name',
  TELEMETRY_TOOL: 'telemetry.tool',
  ACTION_NAME: 'action.name',
  FREE_RAM_MB: 'system.free_ram_mb',
  FREE_STORAGE_MB: 'system.free_storage_mb',
  NET_SPEED_MBPS: 'network.speed_mbps',
  NET_TYPE: 'network.type',
  STEP_NAME: 'step.name',
  STEP_STATUS: 'step.status',
  STEP_DATA: 'step.data',
  EXCEPTION_TYPE: 'exception.type',
  EXCEPTION_MESSAGE: 'exception.message',
} as const;

interface NetworkInformationLike {
  downlink?: number;
  effectiveType?: string;
  type?: string;
}

/** Map the browser's NetworkInformation.type/effectiveType to the contract's network.type enum. */
function resolveNetworkType(conn: NetworkInformationLike | undefined): string {
  const raw = (conn?.type ?? '').toLowerCase();
  if (raw === 'wifi') return 'wifi';
  if (raw === 'ethernet') return 'ethernet';
  if (raw === 'cellular') return 'cellular';
  if (raw === 'none') return 'none';
  // effectiveType (4g/3g/...) implies a cellular-like connection when type is absent.
  if (conn?.effectiveType) return 'cellular';
  // Browsers commonly don't expose connection.type; default to wifi for a desktop demo.
  return 'wifi';
}

/**
 * Sample device/network/system signals from available browser APIs.
 * The web platform cannot read true free RAM/storage synchronously, so we estimate:
 *  - free_ram_mb from performance.memory (Chromium) when present, else a nominal value
 *  - free_storage_mb from the StorageManager estimate cached at startup
 *  - network.speed_mbps from NetworkInformation.downlink
 * These ride as attributes (the collector's spanmetrics connector turns them into metrics).
 */
export interface SampledDeviceInfo {
  deviceModel: string;
  deviceManufacturer: string;
  osVersion: string;
}

let cachedFreeStorageMb = 0;

/** Kick off the async storage estimate once; result is read synchronously thereafter. */
export async function primeStorageEstimate(): Promise<void> {
  try {
    if (typeof navigator !== 'undefined' && navigator.storage?.estimate) {
      const est = await navigator.storage.estimate();
      const quota = est.quota ?? 0;
      const usage = est.usage ?? 0;
      cachedFreeStorageMb = Math.max(0, Math.round((quota - usage) / (1024 * 1024)));
    }
  } catch {
    /* ignore — leave at 0 */
  }
}

function sampleFreeRamMb(): number {
  const perf = performance as Performance & {
    memory?: { jsHeapSizeLimit: number; usedJSHeapSize: number };
  };
  if (perf.memory) {
    const free = perf.memory.jsHeapSizeLimit - perf.memory.usedJSHeapSize;
    return Math.max(0, Math.round(free / (1024 * 1024)));
  }
  return 0;
}

function sampleNetwork(): { speedMbps: number; type: string } {
  const conn = (navigator as Navigator & { connection?: NetworkInformationLike }).connection;
  return {
    speedMbps: typeof conn?.downlink === 'number' ? conn.downlink : 0,
    type: resolveNetworkType(conn),
  };
}

/** Parse a coarse OS/version + device hint from the UA / UA-CH for the resource. */
export function detectDeviceInfo(): SampledDeviceInfo {
  const ua = typeof navigator !== 'undefined' ? navigator.userAgent : '';
  const uaData = (navigator as Navigator & { userAgentData?: { platform?: string } })
    .userAgentData;
  const platform = uaData?.platform || (navigator as Navigator)?.platform || 'unknown';

  let osVersion = platform;
  const mac = /Mac OS X ([0-9_]+)/.exec(ua);
  const win = /Windows NT ([0-9.]+)/.exec(ua);
  const android = /Android ([0-9.]+)/.exec(ua);
  if (mac) osVersion = `macOS ${mac[1].replace(/_/g, '.')}`;
  else if (win) osVersion = `Windows ${win[1]}`;
  else if (android) osVersion = `Android ${android[1]}`;

  // The web has no real device model; report the browser engine as the closest analogue.
  let deviceModel = 'web-browser';
  let deviceManufacturer = 'unknown';
  if (/Chrome\//.test(ua)) {
    deviceModel = 'Chrome';
    deviceManufacturer = 'Google';
  } else if (/Firefox\//.test(ua)) {
    deviceModel = 'Firefox';
    deviceManufacturer = 'Mozilla';
  } else if (/Safari\//.test(ua)) {
    deviceModel = 'Safari';
    deviceManufacturer = 'Apple';
  }
  return { deviceModel, deviceManufacturer, osVersion };
}

/** Common resource-level attributes shared by every span & log. */
export function commonResourceAttributes(tool: TelemetryTool): Attributes {
  const dev = detectDeviceInfo();
  return {
    [ATTR.SERVICE_NAME]: SERVICE_NAME,
    [ATTR.USER_ID]: DEMO_USER_ID,
    [ATTR.APP_VERSION]: APP_VERSION,
    [ATTR.DEVICE_MODEL]: dev.deviceModel,
    [ATTR.DEVICE_MANUFACTURER]: dev.deviceManufacturer,
    [ATTR.OS_VERSION]: dev.osVersion,
    [ATTR.TELEMETRY_TOOL]: tool,
  };
}

/**
 * Per-action attributes sampled at action start. Always sets the schema keys explicitly
 * (for parity with native auto-capture) plus telemetry.tool so the value survives onto
 * child spans/logs even when produced by the Embrace arm.
 */
export function actionAttributes(action: ActionName, tool: TelemetryTool): Attributes {
  const net = sampleNetwork();
  return {
    [ATTR.ACTION_NAME]: action,
    [ATTR.TELEMETRY_TOOL]: tool,
    [ATTR.USER_ID]: DEMO_USER_ID,
    [ATTR.APP_VERSION]: APP_VERSION,
    [ATTR.FREE_RAM_MB]: sampleFreeRamMb(),
    [ATTR.FREE_STORAGE_MB]: cachedFreeStorageMb,
    [ATTR.NET_SPEED_MBPS]: net.speedMbps,
    [ATTR.NET_TYPE]: net.type,
  };
}
