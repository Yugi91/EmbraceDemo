package io.embrace.demo.android.telemetry

import android.content.Context
import android.util.Log

/**
 * Starts the Embrace Android SDK via REFLECTION so the OTel arm has zero compile coupling to the
 * Embrace API (whose 9.0 surface differs from the stale public docs). Only invoked in the `embrace`
 * arm. The point is **E1**: does Embrace 9.0 init with NO app_id (embrace-config.json has none)?
 *
 * We log the exact outcome so logcat is the evidence for the E1 verdict.
 */
object EmbraceArm {
    private const val TAG = "EMBRACE-DEMO"

    fun start(ctx: Context): String {
        return try {
            val cls = Class.forName("io.embrace.android.embracesdk.Embrace")
            val instance = cls.getMethod("getInstance").invoke(null)
            val startMethod = instance.javaClass.methods.firstOrNull {
                it.name == "start" && it.parameterTypes.size == 1 &&
                    Context::class.java.isAssignableFrom(it.parameterTypes[0])
            }
            if (startMethod == null) {
                val sigs = instance.javaClass.methods.filter { it.name == "start" }
                    .joinToString { m -> m.parameterTypes.joinToString(prefix = "start(", postfix = ")") { it.simpleName } }
                return "E1: no start(Context) overload found; available: $sigs"
            }
            startMethod.invoke(instance, ctx)
            val started = runCatching {
                instance.javaClass.getMethod("isStarted").invoke(instance) as? Boolean
            }.getOrNull()
            "E1: Embrace.start(Context) invoked with NO app_id; isStarted=$started"
        } catch (t: Throwable) {
            "E1: Embrace start FAILED (no app_id): ${t.javaClass.name}: ${t.message}"
        }.also { Log.i(TAG, it) }
    }
}
