package com.Marriage.Station

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.marriage.station/call_service"
    private val WINDOW_CHANNEL = "com.ms2026/window_manager"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Window manager channel: FLAG_SECURE for screenshot prevention ───────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WINDOW_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecureFlag") {
                    val secure = call.argument<Boolean>("secure") ?: false
                    runOnUiThread {
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

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
                "getDeviceSoundPolicy" -> {
                    val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val notificationManager =
                        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                    val ringerMode = audioManager.ringerMode
                    val isSilentOrVibrate =
                        ringerMode == AudioManager.RINGER_MODE_SILENT ||
                        ringerMode == AudioManager.RINGER_MODE_VIBRATE

                    val isDnd = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val interruptionFilter = notificationManager.currentInterruptionFilter
                        interruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
                    } else {
                        false
                    }

                    result.success(
                        mapOf(
                            "isSilentOrVibrate" to isSilentOrVibrate,
                            "isDnd" to isDnd,
                            "shouldPlayInAppSound" to (!isSilentOrVibrate && !isDnd),
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }
    }
}
