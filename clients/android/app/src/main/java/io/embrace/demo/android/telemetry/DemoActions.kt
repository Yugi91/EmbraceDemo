package io.embrace.demo.android.telemetry

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.opentelemetry.api.common.AttributeKey
import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.logs.Severity
import io.opentelemetry.api.trace.StatusCode
import java.util.concurrent.Executors

/** The 5 demo actions, each emitting telemetry per SCHEMA_CONTRACT. */
class DemoActions(@Suppress("UNUSED_PARAMETER") ctx: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val bg = Executors.newSingleThreadExecutor()
    private fun actionAttr(name: String) =
        Attributes.of(AttributeKey.stringKey("action.name"), name)

    fun delay() = bg.execute {
        val s = Telemetry.newSpan("delay", Telemetry.sampleAttrs("delay"))
        s.addEvent("delay.started")
        Thread.sleep(760)
        s.addEvent("delay.completed")
        s.end()
        Telemetry.log("delay completed ok (760ms)", Severity.INFO, actionAttr("delay"))
    }

    fun workflow(forceFail: Boolean) = bg.execute {
        val parent = Telemetry.newSpan("workflow", Telemetry.sampleAttrs("workflow"))
        parent.addEvent("started")
        for ((step, ms) in listOf("capture" to 80L, "save" to 60L)) {
            val c = Telemetry.newSpan(
                step,
                Attributes.builder()
                    .put("step.name", step).put("step.status", "ok")
                    .put("step.data", "$step:bytes=${ms * 13}").build(),
                parent
            )
            c.addEvent("$step.started"); Thread.sleep(ms); c.addEvent("$step.done"); c.end()
        }
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
            Telemetry.log(
                "workflow failed at sync (HTTP 503)", Severity.ERROR,
                Attributes.builder().put("action.name", "workflow")
                    .put("http.status", 503L).put("step.status", "failure").build()
            )
        } else {
            sync.setAttribute("step.status", "ok"); sync.addEvent("sync.done"); sync.end()
            parent.end()
            Telemetry.log("workflow completed ok", Severity.INFO, actionAttr("workflow"))
        }
    }

    fun caughtError() = bg.execute {
        try {
            throw IllegalStateException("EmbraceGrafanaDemo intentional handled error (action.name=caught_error)")
        } catch (e: Exception) {
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
        val s = Telemetry.newSpan("frames", Telemetry.sampleAttrs("frames"))
        s.addEvent("frames.jank_start")
        repeat(12) { Thread.sleep(120) }   // 12 x 120ms bursts on the UI thread
        s.addEvent("frames.jank_burst_done")
        s.end()
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
}
