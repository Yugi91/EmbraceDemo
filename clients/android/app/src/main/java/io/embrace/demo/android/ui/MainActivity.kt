package io.embrace.demo.android.ui

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.embrace.demo.android.BuildConfig
import io.embrace.demo.android.telemetry.DemoActions

class MainActivity : ComponentActivity() {
    private lateinit var actions: DemoActions

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        actions = DemoActions(applicationContext)
        setContent { DemoScreen(actions) }
        // Autofire if baked in (-Pautofire=true) OR requested at launch via intent extra
        // (`am start --ez autofire true`) — the latter lets one build serve a clean UI launch
        // and a separate data-push launch.
        if (BuildConfig.AUTOFIRE || intent?.getBooleanExtra("autofire", false) == true) runAutofire()
    }

    private fun runAutofire() {
        val h = Handler(Looper.getMainLooper())
        var t = 1500L
        h.postDelayed({ actions.delay() }, t); t += 2500
        h.postDelayed({ actions.workflow(false) }, t); t += 2500
        h.postDelayed({ actions.workflow(true) }, t); t += 2500
        h.postDelayed({ actions.caughtError() }, t); t += 2500
        h.postDelayed({ actions.frames() }, t); t += 3500
        h.postDelayed({ actions.anr() }, t); t += 9000
        h.postDelayed({ actions.crash() }, t)   // crash last — terminates the app
    }
}

@Composable
private fun DemoScreen(actions: DemoActions) {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("EmbraceGrafanaDemo · Android · tool=${BuildConfig.TELEMETRY_TOOL}")
                Button(onClick = { actions.delay() }) { Text("delay") }
                Button(onClick = { actions.workflow(false) }) { Text("workflow (ok)") }
                Button(onClick = { actions.workflow(true) }) { Text("workflow (fail)") }
                Button(onClick = { actions.caughtError() }) { Text("caught error") }
                Button(onClick = { actions.frames() }) { Text("frames (jank)") }
                Button(onClick = { actions.anr() }) { Text("ANR (block 6s)") }
                Button(onClick = { actions.crash() }) { Text("crash") }
            }
        }
    }
}
