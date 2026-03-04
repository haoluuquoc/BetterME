package com.betterme.betterme

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.betterme.betterme/app"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    "closeApp" -> {
                        // Đóng app HOÀN TOÀN - xóa khỏi recents, giải phóng activity
                        finishAndRemoveTask()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
