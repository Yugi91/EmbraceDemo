package io.embrace.demo.android.telemetry

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.embrace.demo.android.BuildConfig
import io.opentelemetry.api.common.AttributeKey
import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.logs.Severity
import io.opentelemetry.api.trace.StatusCode
import java.util.concurrent.Executors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Request

/** The 5 demo actions, each emitting telemetry per SCHEMA_CONTRACT. */
class DemoActions(@Suppress("UNUSED_PARAMETER") ctx: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val bg = Executors.newSingleThreadExecutor()
    private val http = OkHttpClient()
    private val oomChunks = mutableListOf<ByteArray>()   // retained so GC can't reclaim (oom)
    private fun actionAttr(name: String) =
        Attributes.of(AttributeKey.stringKey("action.name"), name)

    /**
     * In the `embrace` arm, ALSO record the action as a completed Embrace span via the Embrace
     * TracingApi so it reaches the Embrace **cloud** dashboard (Traces → Root Spans List), not only
     * Grafana via OTel-Java. No-op in the `otel` arm (Embrace SDK not started → guarded + try/catch).
     */
    private fun embRecord(name: String, startMs: Long) {
        if (BuildConfig.TELEMETRY_TOOL != "embrace") return
        try {
            io.embrace.android.embracesdk.Embrace.getInstance()
                .recordCompletedSpan(name, startMs, System.currentTimeMillis())
        } catch (_: Throwable) { /* SDK not started in this arm — ignore */ }
    }

    /**
     * Parent-aware Embrace span handle (Embrace 9.0 TracingApi) used to NEST the metric tree on the
     * Embrace cloud dashboard. `startMs` back-dates the start so the parent's duration reflects the real
     * work. Returns null in the `otel` arm / on failure (children then record flat). Call [embStop] when done.
     */
    private fun embStart(
        name: String,
        parent: io.embrace.android.embracesdk.spans.EmbraceSpan? = null,
        startMs: Long? = null,
    ): io.embrace.android.embracesdk.spans.EmbraceSpan? {
        if (BuildConfig.TELEMETRY_TOOL != "embrace") return null
        return try {
            io.embrace.android.embracesdk.Embrace.getInstance().startSpan(name, parent, startMs)
        } catch (_: Throwable) { null }
    }

    private fun embStop(span: io.embrace.android.embracesdk.spans.EmbraceSpan?, endMs: Long? = null) {
        if (span == null) return
        try { span.stop(null, endMs) } catch (_: Throwable) { /* ignore */ }
    }

    /** Parent-aware Embrace completed span via the PROVEN `recordCompletedSpan` primitive (the one
     *  `workflow` uses and that demonstrably reaches the Android Embrace cloud). Nests under [parent]
     *  when non-null; records flat (still surfaces) when null. */
    private fun embRecordChild(
        name: String, startMs: Long, endMs: Long,
        parent: io.embrace.android.embracesdk.spans.EmbraceSpan?,
    ) {
        if (BuildConfig.TELEMETRY_TOOL != "embrace") return
        try {
            io.embrace.android.embracesdk.Embrace.getInstance()
                .recordCompletedSpan(name, startMs, endMs, parent = parent)
        } catch (_: Throwable) {
            try { io.embrace.android.embracesdk.Embrace.getInstance().recordCompletedSpan(name, startMs, endMs) } catch (_: Throwable) {}
        }
    }

    /**
     * `metric` perf-span case — a concurrent + nested tree with captured durations:
     *   metric → { A → (C then D), B },  with A ‖ B.
     * Concurrency uses Kotlin COROUTINES (async on Dispatchers.Default; C→D sequential inside A).
     * OTel-Java child spans (→ Grafana) are opened inside the coroutines with explicit parents.
     * OTel-Java child spans (→ Grafana) open inside the coroutines with explicit parents. For the
     * Embrace **cloud** tree, per-task start/end are measured, then emitted on the bg thread: parents
     * `metric`/`A` via `startSpan(parent, startMs)` (back-dated, stopped at their real end), leaves
     * C/D/B via `recordCompletedSpan(parent=…)`. Yields Total Spans 5, Longest Span = A.
     */
    fun metric() = bg.execute {
        fun mAttrs(task: String) = Attributes.builder()
            .put("action.name", "metric").put("task.name", task).build()
        val mStart = System.currentTimeMillis()
        val otelRoot = Telemetry.newSpan("metric", Telemetry.sampleAttrs("metric"))
        otelRoot.addEvent("metric.started")
        val seg = java.util.concurrent.ConcurrentHashMap<String, LongArray>()   // task -> [start, end]
        runBlocking {
            val jobA = async(Dispatchers.Default) {           // A ‖ B
                val aStart = System.currentTimeMillis()
                val otelA = Telemetry.newSpan("A", mAttrs("A"), otelRoot)
                val cStart = System.currentTimeMillis()       // C — sequential, first
                val otelC = Telemetry.newSpan("C", mAttrs("C"), otelA); delay(120); otelC.end()
                seg["C"] = longArrayOf(cStart, System.currentTimeMillis())
                val dStart = System.currentTimeMillis()       // D — sequential, after C
                val otelD = Telemetry.newSpan("D", mAttrs("D"), otelA); delay(90); otelD.end()
                seg["D"] = longArrayOf(dStart, System.currentTimeMillis())
                otelA.end()
                seg["A"] = longArrayOf(aStart, System.currentTimeMillis())
            }
            val jobB = async(Dispatchers.Default) {
                val bStart = System.currentTimeMillis()
                val otelB = Telemetry.newSpan("B", mAttrs("B"), otelRoot); delay(150); otelB.end()
                seg["B"] = longArrayOf(bStart, System.currentTimeMillis())
            }
            jobA.await(); jobB.await()
        }
        otelRoot.addEvent("metric.completed"); otelRoot.end()
        val mEnd = System.currentTimeMillis()

        // Embrace cloud tree — sequential emission on the bg thread (recordCompletedSpan = proven).
        if (BuildConfig.TELEMETRY_TOOL == "embrace") {
            val aSeg = seg["A"]
            val embRoot = embStart("metric", null, mStart)
            val embA = embStart("A", embRoot, aSeg?.get(0))
            seg["C"]?.let { embRecordChild("C", it[0], it[1], embA) }
            seg["D"]?.let { embRecordChild("D", it[0], it[1], embA) }
            seg["B"]?.let { embRecordChild("B", it[0], it[1], embRoot) }
            embStop(embA, aSeg?.get(1)); embStop(embRoot, mEnd)
            if (embRoot == null) embRecordChild("metric", mStart, mEnd, null)      // flat fallback
            if (embA == null) aSeg?.let { embRecordChild("A", it[0], it[1], null) }
        }
        Telemetry.log("metric perf tree done (A‖B, A→C→D)", Severity.INFO, actionAttr("metric"))
    }

    fun workflow(forceFail: Boolean) = bg.execute {
        val wfStart = System.currentTimeMillis()
        val parent = Telemetry.newSpan("workflow", Telemetry.sampleAttrs("workflow"))
        parent.addEvent("started")
        for ((step, ms) in listOf("capture" to 80L, "save" to 60L)) {
            val stepStart = System.currentTimeMillis()
            val c = Telemetry.newSpan(
                step,
                Attributes.builder()
                    .put("step.name", step).put("step.status", "ok")
                    .put("step.data", "$step:bytes=${ms * 13}").build(),
                parent
            )
            c.addEvent("$step.started"); Thread.sleep(ms); c.addEvent("$step.done"); c.end()
            embRecord(step, stepStart)
        }
        val syncStart = System.currentTimeMillis()
        val sync = Telemetry.newSpan(
            "sync",
            Attributes.of(AttributeKey.stringKey("step.name"), "sync"), parent
        )
        sync.addEvent("sync.started"); Thread.sleep(70)
        if (forceFail) {
            sync.setAttribute("step.status", "failure")
            sync.setAttribute("http.status", 503L)
            sync.setAttribute("exception.type", "SyncError")
            sync.setAttribute("exception.message", "sync failed: HTTP 503")
            sync.setStatus(StatusCode.ERROR, "sync failed")
            sync.addEvent("sync.failed"); sync.end()
            parent.setStatus(StatusCode.ERROR, "workflow failed"); parent.end()
            embRecord("sync", syncStart); embRecord("workflow", wfStart)
            Telemetry.log(
                "workflow failed at sync (HTTP 503)", Severity.ERROR,
                Attributes.builder().put("action.name", "workflow")
                    .put("http.status", 503L).put("step.status", "failure").build()
            )
        } else {
            sync.setAttribute("step.status", "ok"); sync.addEvent("sync.done"); sync.end()
            parent.end()
            embRecord("sync", syncStart); embRecord("workflow", wfStart)
            Telemetry.log("workflow completed ok", Severity.INFO, actionAttr("workflow"))
        }
    }

    fun caughtError() = bg.execute {
        val t0 = System.currentTimeMillis()
        try {
            throw IllegalStateException("EmbraceGrafanaDemo intentional handled error (action.name=caught_error)")
        } catch (e: Exception) {
            embRecord("caught_error", t0)
            Telemetry.log(
                "demo handled exception (action.name=caught_error): ${e.message}", Severity.ERROR,
                Attributes.builder()
                    .put("action.name", "caught_error")
                    .put("exception.type", e.javaClass.name)
                    .put("exception.message", e.message ?: "")
                    .put("handled", true).build()
            )
        }
    }

    /** Jank the MAIN thread to exercise slow/frozen frames (E4). */
    fun frames() = main.post {
        val t0 = System.currentTimeMillis()
        val s = Telemetry.newSpan("frames", Telemetry.sampleAttrs("frames"))
        s.addEvent("frames.jank_start")
        repeat(12) { Thread.sleep(120) }   // 12 x 120ms bursts on the UI thread
        s.addEvent("frames.jank_burst_done")
        s.end()
        embRecord("frames", t0)
        Telemetry.log("frames jank burst done (12x120ms)", Severity.WARN, actionAttr("frames"))
    }

    /** Block the MAIN thread > 5s → a real Android ANR (E3). */
    fun anr() = main.post {
        val s = Telemetry.newSpan("anr", Telemetry.sampleAttrs("anr"))
        s.addEvent("anr.block_start")
        Thread.sleep(6000)
        s.addEvent("anr.block_released")
        s.end()
        Telemetry.log("anr: blocked main thread 6s", Severity.WARN, actionAttr("anr"))
    }

    /** Unhandled crash (E2). Flush first so the crash span/log reach Grafana before death. */
    fun crash() = main.post {
        val s = Telemetry.newSpan("crash", Telemetry.sampleAttrs("crash"))
        val ex = RuntimeException("EmbraceGrafanaDemo intentional unhandled crash (action.name=crash)")
        s.recordException(ex)
        s.setStatus(StatusCode.ERROR, "intentional unhandled crash")
        s.end()
        Telemetry.log(ex.message ?: "crash", Severity.ERROR, actionAttr("crash"))
        Telemetry.flush()
        throw ex
    }

    /** Real HTTP GET (L2). Embrace auto-captures OkHttp → shows in the Network view. */
    fun network() = bg.execute {
        val t0 = System.currentTimeMillis()
        val url = "https://jsonplaceholder.typicode.com/todos/1"
        val s = Telemetry.newSpan(
            "network",
            Attributes.builder()
                .put("action.name", "network").put("http.url", url).put("http.method", "GET").build()
        )
        try {
            http.newCall(Request.Builder().url(url).get().build()).execute().use { resp ->
                val body = resp.body?.bytes() ?: ByteArray(0)
                s.setAttribute("http.status_code", resp.code.toLong())
                s.setAttribute("http.response_size", body.size.toLong())
                s.addEvent("network.response")
                if (resp.isSuccessful) {
                    s.end()
                    embRecord("network", t0)
                    Telemetry.log(
                        "network GET ok (HTTP ${resp.code})", Severity.INFO,
                        Attributes.builder().put("action.name", "network")
                            .put("http.status_code", resp.code.toLong())
                            .put("http.response_size", body.size.toLong()).build()
                    )
                } else {
                    s.setStatus(StatusCode.ERROR, "network failed: HTTP ${resp.code}"); s.end()
                    embRecord("network", t0)
                    Telemetry.log(
                        "network GET failed (HTTP ${resp.code})", Severity.ERROR,
                        Attributes.builder().put("action.name", "network")
                            .put("http.status_code", resp.code.toLong()).build()
                    )
                }
            }
        } catch (e: Exception) {
            s.recordException(e)
            s.setStatus(StatusCode.ERROR, "network error"); s.end()
            embRecord("network", t0)
            Telemetry.log(
                "network GET failed: ${e.message}", Severity.ERROR,
                Attributes.builder().put("action.name", "network")
                    .put("exception.type", e.javaClass.name)
                    .put("exception.message", e.message ?: "").build()
            )
        }
    }

    /** Allocate 4MB chunks unbounded until the process is OutOfMemory-killed (L3, intended). */
    fun oom() = bg.execute {
        Telemetry.log("oom: allocating until killed", Severity.WARN, actionAttr("oom"))
        while (true) {
            oomChunks.add(ByteArray(4 * 1024 * 1024))   // 4MB, retained → no GC reclaim
            Thread.sleep(20)
        }
    }
}
