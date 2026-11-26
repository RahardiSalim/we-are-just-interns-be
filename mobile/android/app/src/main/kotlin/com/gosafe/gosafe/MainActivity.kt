package com.gosafe.gosafe

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** The Android side of a ride, called from lib/services/ride.dart over the "gosafe/ride" channel. */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor() // file encryption off the UI thread

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "gosafe/ride").setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    askForNotifications()
                    startForegroundService(
                        Intent(this, RideService::class.java)
                            .putExtra("title", call.argument<String>("title"))
                            .putExtra("body", call.argument<String>("body")),
                    )
                    result.success(null)
                }
                "stopListening" -> {
                    stopService(Intent(this, RideService::class.java))
                    result.success(null)
                }
                "alert" -> {
                    Alerts.show(this, call.argument("title")!!, call.argument("body")!!, call.argument<Boolean>("loud") == true)
                    result.success(null)
                }
                "clearAlert" -> {
                    Alerts.clear(this)
                    result.success(null)
                }
                "encrypt", "decrypt" -> io.execute {
                    val path = call.argument<String>("path")!!
                    runCatching { if (call.method == "encrypt") Vault.encrypt(path) else Vault.decrypt(path) }
                        .onSuccess { runOnUiThread { result.success(it) } }
                        .onFailure { runOnUiThread { result.error("vault", it.message, null) } }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Android 13+ asks before an app may show notifications. Without it the alarm can't reach a locked phone.
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }
}
