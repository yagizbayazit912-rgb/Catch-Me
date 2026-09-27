package com.example.catch_me

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "catch_me/notify"
    private val ongoingId = 1001
    private val alertId = 1002
    private val channelId = "catch_me_presence"
    private val permReq = 4401

    private var pendingTitle = "Catch Me çalışıyor"
    private var pendingBody = "Alta alsan da bölgeler otomatik sahiplenilir."
    private var pendingProgress = -1
    private var pendingMax = 30

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        val args = call.arguments as? Map<*, *>
                        pendingTitle = args?.get("title") as? String ?: pendingTitle
                        pendingBody = args?.get("body") as? String ?: pendingBody
                        pendingProgress = (args?.get("progress") as? Number)?.toInt() ?: -1
                        pendingMax = (args?.get("max") as? Number)?.toInt() ?: 30
                        ensurePermissionAndShow()
                        result.success(true)
                    }
                    "alert" -> {
                        val args = call.arguments as? Map<*, *>
                        val title = args?.get("title") as? String ?: "Catch Me"
                        val body = args?.get("body") as? String ?: ""
                        showAlert(title, body)
                        result.success(true)
                    }
                    "hideTracking" -> {
                        NotificationManagerCompat.from(this).cancel(ongoingId)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permReq) showOngoing()
    }

    private fun ensurePermissionAndShow() {
        createChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    permReq
                )
                return
            }
        }
        showOngoing()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Catch Me takibi",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Bölge sahiplenme ve kira"
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun launchPending(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun showOngoing() {
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(pendingTitle)
            .setContentText(pendingBody)
            .setStyle(NotificationCompat.BigTextStyle().bigText(pendingBody))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(launchPending())
            .setColor(0xFF00FF66.toInt())

        if (pendingProgress >= 0 && pendingMax > 0) {
            builder.setProgress(pendingMax, pendingProgress.coerceIn(0, pendingMax), false)
        }

        NotificationManagerCompat.from(this).notify(ongoingId, builder.build())
    }

    private fun showAlert(title: String, body: String) {
        createChannel()
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(launchPending())
            .setColor(0xFF00FF66.toInt())
            .build()
        NotificationManagerCompat.from(this).notify(alertId, notification)
    }
}
