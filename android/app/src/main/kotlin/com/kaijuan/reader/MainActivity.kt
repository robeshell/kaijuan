package com.kaijuan.reader

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      CHANNEL,
    ).setMethodCallHandler { call, result ->
      if (call.method != "copyImagePng") {
        result.notImplemented()
        return@setMethodCallHandler
      }
      val bytes = call.arguments as? ByteArray
      if (bytes == null || bytes.isEmpty()) {
        result.error("bad_args", "missing png bytes", null)
        return@setMethodCallHandler
      }
      try {
        val file = File(cacheDir, "kaijuan-clipboard.png")
        file.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(
          this,
          "$packageName.fileprovider",
          file,
        )
        val clip = ClipData.newUri(contentResolver, "image/png", uri)
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(clip)
        result.success(true)
      } catch (error: Exception) {
        result.error("copy_failed", error.message, null)
      }
    }
  }

  companion object {
    private const val CHANNEL = "com.kaijuan.reader/clipboard"
  }
}
