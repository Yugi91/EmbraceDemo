import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { App } from './app/app';
import { initTelemetry } from './app/telemetry/telemetry.service';

// Initialize telemetry BEFORE Angular bootstraps so the unhandled-error / Web-Vitals
// instrumentation is installed before any app code can throw or paint (spike E8 wiring).
initTelemetry();

bootstrapApplication(App, appConfig).catch((err) => console.error(err));
