package com.example.booklibrary

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationChannel: MethodChannel? = null
    private var pendingNotificationAction: String? = null
    private var dartReady = false
    private var permissionRequested = false
    private var mediaSession: MediaSession? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        dartReady = true
                        flushNotificationAction()
                        result.success(null)
                    }
                    "update" -> {
                        updateNotification(call.arguments)
                        result.success(null)
                    }
                    "hide" -> {
                        hideNotification()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        handleNotificationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    override fun onDestroy() {
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    private fun handleNotificationIntent(intent: Intent?) {
        val action = intent?.getStringExtra(EXTRA_ACTION) ?: return
        intent.removeExtra(EXTRA_ACTION)
        if (dartReady) {
            notificationChannel?.invokeMethod("action", action)
        } else {
            pendingNotificationAction = action
        }
    }

    private fun flushNotificationAction() {
        val action = pendingNotificationAction ?: return
        pendingNotificationAction = null
        notificationChannel?.invokeMethod("action", action)
    }

    private fun updateNotification(arguments: Any?) {
        val values = arguments as? Map<*, *> ?: return
        val title = values["title"] as? String ?: "Sesli kitap"
        val playing = values["playing"] as? Boolean ?: false
        val positionMs = (values["positionMs"] as? Number)?.toLong() ?: 0L
        val durationMs = (values["durationMs"] as? Number)?.toLong() ?: 0L
        val positionText = values["positionText"] as? String ?: "0:00:00"
        val durationText = values["durationText"] as? String ?: "0:00:00"
        val speed = (values["speed"] as? Number)?.toFloat() ?: 1f

        createNotificationChannel()
        requestNotificationPermission()
        val session = getMediaSession()
        session.isActive = true
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
                .build(),
        )
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_FAST_FORWARD or
                        PlaybackState.ACTION_REWIND or
                        PlaybackState.ACTION_STOP,
                )
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    positionMs,
                    speed,
                )
                .build(),
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText("$positionText / $durationText")
            .setSubText("Sesli kitap")
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setOngoing(playing)
            .setContentIntent(contentPendingIntent())
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
            .addAction(
                android.R.drawable.ic_media_rew,
                "5 saniye geri",
                actionPendingIntent(ACTION_REWIND),
            )
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "Duraklat" else "Oynat",
                actionPendingIntent(ACTION_PLAY_PAUSE),
            )
            .addAction(
                android.R.drawable.ic_media_ff,
                "5 saniye ileri",
                actionPendingIntent(ACTION_FORWARD),
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Durdur",
                actionPendingIntent(ACTION_STOP),
            )

        try {
            getNotificationManager().notify(NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
            // Android 13+ can reject notifications until the user grants permission.
        }
    }

    private fun hideNotification() {
        getNotificationManager().cancel(NOTIFICATION_ID)
        mediaSession?.isActive = false
    }

    private fun getMediaSession(): MediaSession {
        return mediaSession ?: MediaSession(this, "BookLibraryAudio").also {
            it.setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            mediaSession = it
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getNotificationManager().createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Sesli kitap",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Sesli kitap oynatma kontrolleri"
            },
        )
    }

    private fun requestNotificationPermission() {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED &&
            !permissionRequested
        ) {
            permissionRequested = true
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
    }

    private fun getNotificationManager() =
        getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    private fun contentPendingIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        pendingIntentFlags(),
    )

    private fun actionPendingIntent(action: String): PendingIntent = PendingIntent.getActivity(
        this,
        action.hashCode(),
        Intent(this, MainActivity::class.java).apply {
            putExtra(EXTRA_ACTION, action)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        pendingIntentFlags(),
    )

    private fun pendingIntentFlags() = PendingIntent.FLAG_UPDATE_CURRENT or
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    private companion object {
        const val CHANNEL_NAME = "com.example.booklibrary/audio_notification"
        const val CHANNEL_ID = "booklibrary_audio"
        const val NOTIFICATION_ID = 1001
        const val NOTIFICATION_PERMISSION_REQUEST = 1002
        const val EXTRA_ACTION = "booklibrary_audio_action"
        const val ACTION_REWIND = "rewind"
        const val ACTION_PLAY_PAUSE = "playPause"
        const val ACTION_FORWARD = "forward"
        const val ACTION_STOP = "stop"
    }
}
