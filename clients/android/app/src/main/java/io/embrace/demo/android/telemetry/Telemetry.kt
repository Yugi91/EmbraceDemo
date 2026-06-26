package io.embrace.demo.android.telemetry

import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.StatFs
import io.embrace.demo.android.BuildConfig
import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.logs.Logger
import io.opentelemetry.api.logs.Severity
import io.opentelemetry.api.trace.Span
import io.opentelemetry.api.trace.Tracer
import io.opentelemetry.exporter.otlp.http.logs.OtlpHttpLogRecordExporter
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter
import io.opentelemetry.sdk.OpenTelemetrySdk
import io.opentelemetry.sdk.logs.SdkLoggerProvider
import io.opentelemetry.sdk.logs.export.BatchLogRecordProcessor
import io.opentelemetry.sdk.resources.Resource
import io.opentelemetry.sdk.trace.SdkTracerProvider
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor
import java.time.Duration
import java.util.concurrent.TimeUnit

/**
 * plain-OpenTelemetry (Java SDK) pipeline → OTLP/HTTP → self-hosted Grafana (otel-lgtm).
 * This is the F1 baseline arm. The Embrace arm additionally starts the Embrace SDK (see
 * [EmbraceArm]) to test E1 (no-account init); the demo-action telemetry itself flows through
 * this OTel pipeline so the Android client reliably reaches Grafana regardless of arm.
 *
 * All attribute keys follow docs/SCHEMA_CONTRACT.md so one Grafana dashboard works cross-platform.
 */
object Telemetry {
    const val SERVICE_NAME = "embrace-demo-android"
    const val APP_VERSION = "1.0.0+1"
    const val USER_ID = "demo-user-001"

    private lateinit var sdk: OpenTelemetrySdk
    private lateinit var tracerProvider: SdkTracerProvider
    private lateinit var loggerProvider: SdkLoggerProvider
    lateinit var tracer: Tracer
        private set
    lateinit var logger: Logger
        private set
    private lateinit var app: Context

    fun init(context: Context) {
        app = context.applicationContext
        val base = BuildConfig.OTLP_HTTP_ENDPOINT
        val resource = Resource.getDefault().merge(
            Resource.create(
                Attributes.builder()
                    .put("service.name", SERVICE_NAME)
                    .put("telemetry.tool", BuildConfig.TELEMETRY_TOOL)
                    .put("device.model", Build.MODEL)
                    .put("device.manufacturer", Build.MANUFACTURER)
                    .put("os.version", Build.VERSION.RELEASE ?: "")
                    .put("app.version", APP_VERSION)
                    .put("user.id", USER_ID)
                    .build()
            )
        )
        val spanExporter = OtlpHttpSpanExporter.builder()
            .setEndpoint("$base/v1/traces").build()
        val logExporter = OtlpHttpLogRecordExporter.builder()
            .setEndpoint("$base/v1/logs").build()
        tracerProvider = SdkTracerProvider.builder()
            .setResource(resource)
            .addSpanProcessor(
                BatchSpanProcessor.builder(spanExporter)
                    .setScheduleDelay(Duration.ofSeconds(2)).build()
            ).build()
        loggerProvider = SdkLoggerProvider.builder()
            .setResource(resource)
            .addLogRecordProcessor(
                BatchLogRecordProcessor.builder(logExporter)
                    .setScheduleDelay(Duration.ofSeconds(2)).build()
            ).build()
        sdk = OpenTelemetrySdk.builder()
            .setTracerProvider(tracerProvider)
            .setLoggerProvider(loggerProvider)
            .build()
        tracer = sdk.getTracer("embrace-demo-android")
        logger = loggerProvider.get("embrace-demo-android")
    }

    /** Per-action runtime sample (RAM/storage/network) per SCHEMA_CONTRACT. */
    fun sampleAttrs(actionName: String): Attributes {
        val am = app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val freeRamMb = mi.availMem / (1024.0 * 1024.0)
        val stat = StatFs(app.filesDir.absolutePath)
        val freeStorageMb = stat.availableBytes / (1024.0 * 1024.0)
        return Attributes.builder()
            .put("action.name", actionName)
            .put("system.free_ram_mb", freeRamMb)
            .put("system.free_storage_mb", freeStorageMb)
            .put("network.type", networkType())
            .put("network.speed_mbps", 0.0)
            .build()
    }

    private fun networkType(): String = try {
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "unknown"
        }
    } catch (t: Throwable) {
        "unknown"
    }

    fun log(message: String, severity: Severity, extra: Attributes = Attributes.empty()) {
        logger.logRecordBuilder()
            .setSeverity(severity)
            .setSeverityText(severity.name)
            .setBody(message)
            .setAllAttributes(extra)
            .emit()
    }

    fun newSpan(name: String, attrs: Attributes, parent: Span? = null): Span {
        val b = tracer.spanBuilder(name).setAllAttributes(attrs)
        if (parent != null) {
            b.setParent(io.opentelemetry.context.Context.current().with(parent))
        }
        return b.startSpan()
    }

    /** Block until batches are exported — used before an intentional crash. */
    fun flush() {
        try {
            tracerProvider.forceFlush().join(5, TimeUnit.SECONDS)
            loggerProvider.forceFlush().join(5, TimeUnit.SECONDS)
        } catch (_: Throwable) {
        }
    }
}
