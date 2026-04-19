package com.Marriage.Station

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.marriage.station/call_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCallService" -> {
                    val callType = call.argument<String>("callType") ?: "audio"
                    val callerName = call.argument<String>("callerName") ?: "Unknown"
                    val callId = call.argument<String>("callId") ?: ""
                    val isIncoming = call.argument<Boolean>("isIncoming") ?: true

                    CallForegroundService.startCallService(
                        applicationContext,
                        callType,
                        callerName,
                        callId,
                        isIncoming
                    )
                    result.success(true)
                }
                "stopCallService" -> {
                    CallForegroundService.stopCallService(applicationContext)
                    result.success(true)
                }
                "updateCallNotification" -> {
                    // Update notification (restart service with updated info)
                    val callType = call.argument<String>("callType") ?: "audio"
                    val callerName = call.argument<String>("callerName") ?: "Unknown"
                    val isOngoing = call.argument<Boolean>("isOngoing") ?: true

                    if (isOngoing) {
                        CallForegroundService.startCallService(
                            applicationContext,
                            callType,
                            callerName,
                            "",
                            false
                        )
                    }
                    result.success(true)
                }
                "isServiceRunning" -> {
                    // For simplicity, return false - service tracking can be improved
                    result.success(false)
                }
                "enableAudioFocus" -> {
                    CallForegroundService.enableAudioFocus(applicationContext)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
