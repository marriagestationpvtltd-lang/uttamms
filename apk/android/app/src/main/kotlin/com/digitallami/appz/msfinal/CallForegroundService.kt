package com.Marriage.Station

import android.app.*
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import io.flutter.Log
import java.util.concurrent.TimeUnit

class CallForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private val TAG = "CallForegroundService"
    private val CHANNEL_ID = "call_foreground_channel"
    private val NOTIFICATION_ID = 1001

    companion object {
        const val ACTION_START_CALL = "START_CALL"
        const val ACTION_END_CALL = "END_CALL"
        const val ACTION_ACCEPT_CALL = "ACCEPT_CALL"
        const val ACTION_DECLINE_CALL = "DECLINE_CALL"
        const val ACTION_ENABLE_AUDIO = "ENABLE_AUDIO"

        const val EXTRA_CALL_TYPE = "call_type"
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_CALL_ID = "call_id"
        const val EXTRA_IS_INCOMING = "is_incoming"

        fun startCallService(context: Context, callType: String, callerName: String, callId: String, isIncoming: Boolean) {
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_START_CALL
                putExtra(EXTRA_CALL_TYPE, callType)
                putExtra(EXTRA_CALLER_NAME, callerName)
                putExtra(EXTRA_CALL_ID, callId)
                putExtra(EXTRA_IS_INCOMING, isIncoming)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopCallService(context: Context) {
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_END_CALL
            }
            context.stopService(intent)
        }

        fun enableAudioFocus(context: Context) {
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_ENABLE_AUDIO
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "CallForegroundService created")
        createNotificationChannel()
        acquireWakeLock()
        // Audio focus is requested explicitly via ACTION_ENABLE_AUDIO once the call
        // is actually connected, so that the ringtone is not interrupted during
        // outgoing call ringing.
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent?.action}")

        when (intent?.action) {
            ACTION_START_CALL -> {
                val callType = intent.getStringExtra(EXTRA_CALL_TYPE) ?: "audio"
                val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Unknown"
                val callId = intent.getStringExtra(EXTRA_CALL_ID) ?: ""
                val isIncoming = intent.getBooleanExtra(EXTRA_IS_INCOMING, true)

                startForegroundCall(callType, callerName, isIncoming)
            }
            ACTION_END_CALL -> {
                stopForegroundService()
            }
            ACTION_ACCEPT_CALL -> {
                // Handle accept call action
                handleAcceptCall()
            }
            ACTION_DECLINE_CALL -> {
                // Handle decline call action
                handleDeclineCall()
            }
            ACTION_ENABLE_AUDIO -> {
                // Request audio focus now that the call is connected
                configureAudioForCall()
            }
        }

        return START_STICKY
    }

    private fun startForegroundCall(callType: String, callerName: String, isIncoming: Boolean) {
        val notification = createCallNotification(callType, callerName, isIncoming)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val serviceType = if (callType == "video") {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            startForeground(NOTIFICATION_ID, notification, serviceType)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        Log.d(TAG, "Started foreground service for $callType call with $callerName")
    }

    private fun createCallNotification(callType: String, callerName: String, isIncoming: Boolean): Notification {
        val title = if (isIncoming) "Incoming $callType call" else "Ongoing $callType call"
        val text = if (isIncoming) "$callerName is calling..." else "In call with $callerName"

        val icon = if (callType == "video") {
            android.R.drawable.ic_menu_camera
        } else {
            android.R.drawable.ic_menu_call
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(icon)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentIntent)
            .setAutoCancel(false)
            .setSound(null)
            .setVibrate(null)
            .setSilent(true)

        // Add action buttons for incoming calls
        if (isIncoming) {
            val acceptIntent = Intent(this, CallForegroundService::class.java).apply {
                action = ACTION_ACCEPT_CALL
            }
            val acceptPendingIntent = PendingIntent.getService(
                this,
                0,
                acceptIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val declineIntent = Intent(this, CallForegroundService::class.java).apply {
                action = ACTION_DECLINE_CALL
            }
            val declinePendingIntent = PendingIntent.getService(
                this,
                1,
                declineIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            builder.addAction(
                android.R.drawable.ic_menu_call,
                "Accept",
                acceptPendingIntent
            )
            builder.addAction(
                android.R.drawable.ic_delete,
                "Decline",
                declinePendingIntent
            )
        } else {
            // Add end call button for ongoing calls
            val endIntent = Intent(this, CallForegroundService::class.java).apply {
                action = ACTION_END_CALL
            }
            val endPendingIntent = PendingIntent.getService(
                this,
                2,
                endIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "End Call",
                endPendingIntent
            )
        }

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Call Service"
            val descriptionText = "Keeps call active in background"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "MarriageStation::CallWakeLock"
        ).apply {
            // Hold the CPU for up to 30 minutes so normal calls survive screen lock/background,
            // while still guaranteeing the lock is released even if cleanup is missed.
            acquire(TimeUnit.MINUTES.toMillis(30))
            Log.d(TAG, "WakeLock acquired")
        }
    }

    private fun configureAudioForCall() {
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager?.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager?.isMicrophoneMute = false

        val focusResult = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAcceptsDelayedFocusGain(false)
                .build()
            audioFocusRequest = focusRequest
            audioManager?.requestAudioFocus(focusRequest) ?: AudioManager.AUDIOFOCUS_REQUEST_FAILED
        } else {
            @Suppress("DEPRECATION")
            audioManager?.requestAudioFocus(
                null,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN
            ) ?: AudioManager.AUDIOFOCUS_REQUEST_FAILED
        }

        Log.d(TAG, "Audio configured for call: focusResult=$focusResult")
    }

    private fun resetAudioConfiguration() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { request ->
                audioManager?.abandonAudioFocusRequest(request)
            }
        } else {
            @Suppress("DEPRECATION")
            audioManager?.abandonAudioFocus(null)
        }

        audioManager?.mode = AudioManager.MODE_NORMAL
        audioFocusRequest = null
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "WakeLock released")
            }
        }
        wakeLock = null
    }

    private fun handleAcceptCall() {
        Log.d(TAG, "Accept call action triggered")
        // The actual call acceptance will be handled by Flutter side
        // Just update notification to show ongoing call
        val notification = createCallNotification("audio", "User", false)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun handleDeclineCall() {
        Log.d(TAG, "Decline call action triggered")
        stopForegroundService()
    }

    private fun stopForegroundService() {
        Log.d(TAG, "Stopping foreground service")
        releaseWakeLock()
        stopForeground(true)
        stopSelf()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        Log.d(TAG, "CallForegroundService destroyed")
        releaseWakeLock()
        super.onDestroy()
    }
}
