package io.embrace.demo.android

import android.app.Application
import android.util.Log
import io.embrace.demo.android.telemetry.EmbraceArm
import io.embrace.demo.android.telemetry.Telemetry

class DemoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Embrace arm: start the Embrace SDK no-account (E1) BEFORE anything else.
        if (BuildConfig.TELEMETRY_TOOL == "embrace") {
            EmbraceArm.start(this)
        }
        // Both arms: the explicit demo telemetry flows through the OTel-Java pipeline so the
        // Android client reliably reaches the self-hosted Grafana regardless of arm.
        Telemetry.init(this)
        Log.i(
            "EMBRACE-DEMO",
            "Telemetry init: tool=${BuildConfig.TELEMETRY_TOOL} endpoint=${BuildConfig.OTLP_HTTP_ENDPOINT} autofire=${BuildConfig.AUTOFIRE}"
        )
    }
}
