package com.rakib.dirxplore

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.nexus/downloads"
    private var methodChannel: MethodChannel? = null

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.getStringExtra("action") ?: ""
            val id = intent?.getIntExtra("id", 0) ?: 0
            
            val flutterAction = when (action) {
                DownloadService.ACTION_PAUSE -> "pause"
                DownloadService.ACTION_RESUME -> "resume"
                DownloadService.ACTION_CANCEL -> "cancel"
                else -> ""
            }
            
            if (flutterAction.isNotEmpty()) {
                methodChannel?.invokeMethod("onNotificationAction", mapOf(
                    "action" to flutterAction,
                    "id" to id
                ))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val url = call.argument<String>("url") ?: ""
                    val filename = call.argument<String>("filename") ?: ""
                    val idParam = call.argument<Int>("id") ?: 0
                    val id = if (idParam == 0) 1001 else idParam
                    
                    val intent = Intent(this, DownloadService::class.java).apply {
                        action = "START_DOWNLOAD"
                        putExtra("url", url)
                        putExtra("filename", filename)
                        putExtra("id", id)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopForegroundService" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val intent = Intent(this, DownloadService::class.java).apply {
                        action = "STOP_DOWNLOAD"
                        putExtra("id", id)
                    }
                    startService(intent)
                    result.success(true)
                }
                "updateProgress" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val progress = call.argument<Int>("progress") ?: 0
                    val speedStr = call.argument<String>("speed") ?: ""
                    val intent = Intent(this, DownloadService::class.java).apply {
                        action = "UPDATE_PROGRESS"
                        putExtra("id", id)
                        putExtra("progress", progress)
                        putExtra("speed", speedStr)
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Register receiver for notification actions
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(notificationReceiver, IntentFilter(DownloadService.NOTIFICATION_ACTION_BROADCAST), Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(notificationReceiver, IntentFilter(DownloadService.NOTIFICATION_ACTION_BROADCAST))
        }
    }

    override fun onDestroy() {
        unregisterReceiver(notificationReceiver)
        super.onDestroy()
    }
}
