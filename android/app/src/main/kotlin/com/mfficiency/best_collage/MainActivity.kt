package com.mfficiency.best_collage

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // In-app updates (lib/src/services/update_service.dart): download the
        // APK with DownloadManager, then install it through a PackageInstaller
        // session.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bestcollage/update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // DownloadManager runs the transfer as a system service: it
                // survives the app being backgrounded and resumes by itself
                // when the network drops or switches Wi-Fi <-> mobile.
                "startBackgroundDownload" -> {
                    val url = call.argument<String>("url")
                    val fileName = call.argument<String>("fileName")
                    if (url == null || fileName == null) {
                        result.error("bad-args", "url/fileName missing", null)
                        return@setMethodCallHandler
                    }
                    try {
                        // DownloadManager can only write into the app's
                        // *external* private storage (no permission needed),
                        // not its internal filesDir.
                        val baseDir = getExternalFilesDir(null)
                        if (baseDir == null) {
                            result.error(
                                "download-failed", "External storage unavailable", null
                            )
                            return@setMethodCallHandler
                        }
                        val destDir = File(baseDir, "updates")
                        destDir.mkdirs()
                        // Old update APKs are no longer needed.
                        destDir.listFiles()?.forEach { it.delete() }
                        val destFile = File(destDir, fileName)
                        val downloadManager =
                            getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                        // Silent: the automatic background download shows no
                        // notification (DOWNLOAD_WITHOUT_NOTIFICATION); the app
                        // asks once the APK is complete.
                        val silent = call.argument<Boolean>("silent") == true
                        val request = DownloadManager.Request(Uri.parse(url))
                            .setTitle("BestCollage update")
                            .setDestinationUri(Uri.fromFile(destFile))
                            .setNotificationVisibility(
                                if (silent) DownloadManager.Request.VISIBILITY_HIDDEN
                                else DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                            )
                            .setAllowedNetworkTypes(
                                DownloadManager.Request.NETWORK_WIFI or
                                    DownloadManager.Request.NETWORK_MOBILE
                            )
                            .setAllowedOverMetered(true)
                            .setAllowedOverRoaming(true)
                        val id = downloadManager.enqueue(request)
                        result.success(mapOf("downloadId" to id))
                    } catch (e: Exception) {
                        result.error("download-failed", e.message, null)
                    }
                }
                // Snapshot of a download: status, bytes for a progress bar,
                // and the local file path once it finished.
                "queryDownload" -> {
                    val id = call.argument<Number>("downloadId")?.toLong()
                    if (id == null) {
                        result.error("bad-args", "downloadId missing", null)
                        return@setMethodCallHandler
                    }
                    val downloadManager =
                        getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    val cursor = downloadManager.query(
                        DownloadManager.Query().setFilterById(id)
                    )
                    if (cursor == null) {
                        result.success(mapOf("status" to "failed", "reason" to "not-found"))
                        return@setMethodCallHandler
                    }
                    cursor.use {
                        if (!it.moveToFirst()) {
                            result.success(
                                mapOf("status" to "failed", "reason" to "not-found")
                            )
                            return@setMethodCallHandler
                        }
                        val status = when (
                            it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                        ) {
                            DownloadManager.STATUS_SUCCESSFUL -> "successful"
                            DownloadManager.STATUS_FAILED -> "failed"
                            DownloadManager.STATUS_RUNNING -> "running"
                            DownloadManager.STATUS_PAUSED -> "paused"
                            else -> "pending"
                        }
                        val localUri = it.getString(
                            it.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
                        )
                        result.success(
                            mapOf(
                                "status" to status,
                                "bytesDownloaded" to it.getLong(
                                    it.getColumnIndexOrThrow(
                                        DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR
                                    )
                                ),
                                "bytesTotal" to it.getLong(
                                    it.getColumnIndexOrThrow(
                                        DownloadManager.COLUMN_TOTAL_SIZE_BYTES
                                    )
                                ),
                                "localPath" to localUri?.let { uri -> Uri.parse(uri).path },
                                "reason" to it.getInt(
                                    it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)
                                ),
                            )
                        )
                    }
                }
                "cancelDownload" -> {
                    val id = call.argument<Number>("downloadId")?.toLong()
                    if (id == null) {
                        result.error("bad-args", "downloadId missing", null)
                        return@setMethodCallHandler
                    }
                    val downloadManager =
                        getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    downloadManager.remove(id)
                    result.success(null)
                }
                // Opens the system installer for a downloaded APK. Returns
                // "needs-permission" (after opening the "install unknown
                // apps" screen for this app) when that one-time permission
                // is still missing.
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad-args", "path missing", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()
                    ) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success("needs-permission")
                        return@setMethodCallHandler
                    }
                    // A PackageInstaller session (ApkInstaller.kt): Android
                    // shows only "Update this app?". Copying the APK into the
                    // session blocks, so it runs off the main thread.
                    val main = Handler(Looper.getMainLooper())
                    Thread {
                        val error = try {
                            ApkInstaller.install(applicationContext, File(path))
                            null
                        } catch (e: Exception) {
                            Log.w("ApkInstaller", "install failed", e)
                            e.message ?: e.toString()
                        }
                        main.post {
                            if (error == null) result.success("ok")
                            else result.error("install-failed", error, null)
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
}
