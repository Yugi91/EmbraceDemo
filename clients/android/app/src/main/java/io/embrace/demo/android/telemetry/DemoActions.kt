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
     * Parent-aware Embrace span (Embrace 9.0 TracingApi) so the metric tree is **nested** on the
     * Embrace cloud dashboard, not flat like [embRecord]. Returns the started [EmbraceSpan] (or null
     * in the `otel` arm / on failure). Pass `parent=null` for a root span. Call [embStop] when done.
     */
    private fun embStart(
        name: String,
        parent: io.embrace.android.embracesdk.spans.EmbraceSpan? = null,
    ): io.embrace.android.embracesdk.spans.EmbraceSpan? {
        if (BuildConfig.TELEMETRY_TOOL != "embrace") return null
        return try {
            io.embrace.android.embracesdk.Embrace.getInstance().startSpan(name, parent)
        } catch (_: Throwable) { null }
    }

    private fun embStop(span: io.embrace.android.embracesdk.spans.EmbraceSpan?) {
        if (span == null) return
        try { span.stop() } catch (_: Throwable) { /* SDK not started in this arm — ignore */ }
    }

    /**
     * Builds a concurrent + nested perf-span tree to exercise the rich "metric" case in both arms:
     *
     *   metric            (ROOT; created on the bg thread)
     *   ├── A             (own thread, IN PARALLEL with B)
     *   │   ├── C         (own thread; SEQUENTIAL — first,  ~120ms)
     *   │   └── D         (own thread; SEQUENTIAL — after C, ~90ms)
     *   └── B             (own thread, IN PARALLEL with A,  ~150ms)
     *
     * Each node opens an OTel-Java child span (correct `parent` arg) AND, in the embrace arm, a
     * parent-aware Embrace child span via [embStart]; spans end bottom-up once their `Thread.sleep`
     * work finishes. `metric` ends only after A and B have both joined → its duration ≈ max(A, B).
     */
    fun metric() = bg.execute {
        val rootStart = System.currentTimeMillis()
        val root = Telemetry.newSpan("metric", Telemetry.sampleAttrs("metric"))
        root.addEvent("metric.started")
        val embRoot = embStart("metric", null)

        // Runs a leaf: OTel child span (under `otelParent`) + Embrace child span (under `embParent`),
        // sleeps `workMs` to capture a real duration, then ends both spans.
        fun runLeaf(
            name: String,
            workMs: Long,
            otelParent: io.opentelemetry.api.trace.Span,
            embParent: io.embrace.android.embracesdk.spans.EmbraceSpan?,
        ) {
            val span = Telemetry.newSpan(
                name,
                Attributes.builder()
                    .put("action.name", "metric")
                    .put("task.name", name)
                    .put("work.ms", workMs)
                    .put("thread.name", Thread.currentThread().name)
                    .build(),
                otelParent
            )
            val embSpan = embStart(name, embParent)
            span.addEvent("$name.started")
            Thread.sleep(workMs)
            span.addEvent("$name.done")
            span.end()
            embStop(embSpan)
        }

        // A: own thread, parallel with B. Inside: C then D, sequential (each its own thread).
        val threadA = Thread {
            val aStart = System.currentTimeMillis()
            val spanA = Telemetry.newSpan(
                "A",
                Attributes.builder()
                    .put("action.name", "metric")
                    .put("task.name", "A")
                    .put("thread.name", Thread.currentThread().name)
                    .build(),
                root
            )
            val embA = embStart("A", embRoot)
            spanA.addEvent("A.started")

            // C — sequential first.
            val threadC = Thread { runLeaf("C", 120L, spanA, embA) }
            threadC.start(); threadC.join()
            // D — sequential after C.
            val threadD = Thread { runLeaf("D", 90L, spanA, embA) }
            threadD.start(); threadD.join()

            spanA.setAttribute("work.ms", System.currentTimeMillis() - aStart)
            spanA.addEvent("A.done")
            spanA.end()
            embStop(embA)
        }
        // B: own thread, parallel with A.
        val threadB = Thread { runLeaf("B", 150L, root, embRoot) }

        threadA.start(); threadB.start()   // A ‖ B
        threadA.join(); threadB.join()     // join both before ending the root

        root.setAttribute("work.ms", System.currentTimeMillis() - rootStart)
        root.addEvent("metric.completed")
        root.end()
        embStop(embRoot)
        Telemetry.log(
            "metric perf tree done (A‖B, A→C→D)", Severity.INFO, actionAttr("metric")
        )
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
