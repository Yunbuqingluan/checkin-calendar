package com.yunluan.checkincalendar

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.yunluan.checkincalendar/files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val name = call.argument<String>("name")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (name == null || bytes == null) {
                            result.error("bad_args", "name/bytes 不能为空", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToDownloads(name, bytes))
                        } catch (e: Exception) {
                            result.error("save_failed", e.message ?: "写入失败", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 写到「下载/打卡日历导出/」，文件管理器里能直接看到，不用再自己挑路径。
     * Android 10+ 走 MediaStore，不需要额外权限；
     * 更低版本写公共下载目录，失败时由 Dart 侧回退到应用目录。
     */
    private fun saveToDownloads(name: String, bytes: ByteArray): String {
        val folder = "打卡日历导出"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "application/json")
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/$folder"
                )
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("系统没有返回文件位置")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("打开文件失败")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "下载/$folder/$name"
        }

        @Suppress("DEPRECATION")
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            folder
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("无法创建目录，请检查存储权限")
        }
        val file = File(dir, name)
        file.writeBytes(bytes)
        MediaScannerConnection.scanFile(
            this,
            arrayOf(file.absolutePath),
            arrayOf("application/json"),
            null
        )
        return "下载/$folder/$name"
    }
}
