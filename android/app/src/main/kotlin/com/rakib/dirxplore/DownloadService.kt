package com.rakib.dirxplore

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class DownloadService : Service() {
    companion object {
        const val CHANNEL_ID = "DownloadServiceChannel"
        const val ACTION_PAUSE = "com.rakib.dirxplore.PAUSE"
        const val ACTION_RESUME = "com.rakib.dirxplore.RESUME"
        const val ACTION_CANCEL = "com.rakib.dirxplore.CANCEL"
        
        // Broadcast actions for MainActivity
        const val NOTIFICATION_ACTION_BROADCAST = "com.rakib.dirxplore.NOTIFICATION_ACTION"
        const val CHANNEL_COMPLETE_ID = "DownloadCompleteChannel"
    }

    private val notificationManager: NotificationManager by lazy {
        getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    }

    private var lastFilename: String = "Downloading..."
    private var isPaused: Boolean = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val id = intent?.getIntExtra("id", 1001) ?: 1001

        when (action) {
            "START_DOWNLOAD" -> {
                lastFilename = intent.getStringExtra("filename") ?: "Unknown File"
                isPaused = false
                startForeground(id, createNotification(lastFilename, 0, "Starting...", false))
            }
            "UPDATE_PROGRESS" -> {
                val progress = intent.getIntExtra("progress", 0)
                val speed = intent.getStringExtra("speed") ?: ""
                val eta = intent.getStringExtra("eta") ?: ""
                val size = intent.getStringExtra("size") ?: ""
                isPaused = false
                notificationManager.notify(id, createNotification(lastFilename, progress, speed, false, eta, size))
            }
            "STOP_DOWNLOAD" -> {
                val isSuccess = intent.getBooleanExtra("success", false)
                val isError = intent.getBooleanExtra("error", false)
                val filename = intent.getStringExtra("filename") ?: lastFilename
                
                stopForeground(true)
                if (isSuccess) {
                    showCompletionNotification(filename, "Download Complete")
                } else if (isError) {
                    val msg = intent.getStringExtra("error_msg") ?: "Download Failed"
                    showCompletionNotification(filename, msg)
                }
                stopSelf()
            }
            ACTION_PAUSE, ACTION_RESUME, ACTION_CANCEL -> {
                // Forward action to MainActivity via broadcast
                val broadcastIntent = Intent(NOTIFICATION_ACTION_BROADCAST).apply {
                    putExtra("action", action)
                    putExtra("id", id)
                    setPackage(packageName)
                }
                sendBroadcast(broadcastIntent)
                
                // Update notification state toggle if it's pause/resume
                if (action == ACTION_PAUSE) {
                    isPaused = true
                    notificationManager.notify(id, createNotification(lastFilename, -1, "Paused", true, "", ""))
                } else if (action == ACTION_RESUME) {
                    isPaused = false
                    notificationManager.notify(id, createNotification(lastFilename, -1, "Resuming...", false, "", ""))
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun showCompletionNotification(fileName: String, status: String) {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, pendingIntentFlags)

        val builder = NotificationCompat.Builder(this, CHANNEL_COMPLETE_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(fileName)
            .setContentText(status)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)

        notificationManager.notify(System.currentTimeMillis().toInt(), builder.build())
    }

    private fun createNotification(title: String, progress: Int, contentText: String, paused: Boolean, eta: String = "", size: String = ""): android.app.Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentPendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, pendingIntentFlags)

        // Pause/Resume Action
        val actionIntent = Intent(this, DownloadService::class.java).apply {
            action = if (paused) ACTION_RESUME else ACTION_PAUSE
            putExtra("id", 1001) // Using 1001 as default
        }
        val actionPendingIntent = PendingIntent.getService(this, 1, actionIntent, pendingIntentFlags)
        val actionLabel = if (paused) "Resume" else "Pause"
        val actionIcon = if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause

        // Cancel Action
        val cancelIntent = Intent(this, DownloadService::class.java).apply {
            action = ACTION_CANCEL
            putExtra("id", 1001)
        }
        val cancelPendingIntent = PendingIntent.getService(this, 2, cancelIntent, pendingIntentFlags)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("$contentText" + if (size.isNotEmpty()) " • $size" else "")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .addAction(actionIcon, actionLabel, actionPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelPendingIntent)

        if (eta.isNotEmpty() && !paused) {
            builder.setSubText("ETA: $eta")
        } else if (paused) {
            builder.setSubText("Paused")
        } else {
            builder.setSubText("Downloading...")
        }

        if (progress >= 0) {
            builder.setProgress(100, progress, progress == 0)
        }

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Download Service Channel",
                NotificationManager.IMPORTANCE_LOW 
            )
            notificationManager.createNotificationChannel(serviceChannel)

            val completeChannel = NotificationChannel(
                CHANNEL_COMPLETE_ID,
                "Download Complete Notifications",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            notificationManager.createNotificationChannel(completeChannel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
