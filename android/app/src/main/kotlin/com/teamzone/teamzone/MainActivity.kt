package com.teamzone.teamzone

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // teamzone/share: the system share sheet for a text, such as a
    // survey link sent with WhatsApp, a text message or email.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "teamzone/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareText") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val text = call.argument<String>("text")
                if (text.isNullOrEmpty()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    call.argument<String>("subject")?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                }
                try {
                    startActivity(Intent.createChooser(send, null))
                    result.success(true)
                } catch (error: Exception) {
                    result.success(false)
                }
            }
    }
}
