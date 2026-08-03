package com.kaijuan.reader

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
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
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      UPDATE_CHANNEL,
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "installApk" -> installApk(call, result)
        else -> result.notImplemented()
      }
    }
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      LANGUAGE_CHANNEL,
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "openDictionary", "openTranslation" -> openLanguage(call, result)
        else -> result.notImplemented()
      }
    }
  }

  private fun openLanguage(call: MethodCall, result: MethodChannel.Result) {
    val text = call.argument<String>("text")?.trim()
    if (text.isNullOrEmpty()) {
      result.success(false)
      return
    }

    val dictionary = call.method == "openDictionary"
    val candidateIntents = buildList {
      if (dictionary && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        add(
          Intent(ACTION_DEFINE).apply {
            putExtra(Intent.EXTRA_TEXT, text)
          },
        )
      }
      add(processTextIntent(text))
    }
    val browserPackages = browserPackages()
    val selectedIntent = candidateIntents.firstOrNull { intent ->
      queryLanguageHandlers(intent, browserPackages).isNotEmpty()
    }
    if (selectedIntent == null) {
      result.success(false)
      return
    }
    val handlers = queryLanguageHandlers(selectedIntent, browserPackages)
    val browserComponents = browserComponents()

    val chooserTitle = if (dictionary) "选择词典应用" else "选择翻译应用"
    val chooser = Intent.createChooser(selectedIntent, chooserTitle)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && browserComponents.isNotEmpty()) {
      chooser.putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, browserComponents.toTypedArray())
    }
    try {
      // Keep Android's native chooser UI, but never let a browser become the
      // only visible result for a dictionary/translation action.
      if (handlers.size == 1) {
        startActivity(selectedIntent.setComponent(handlers.first()))
      } else {
        startActivity(chooser)
      }
      result.success(true)
    } catch (_: ActivityNotFoundException) {
      result.success(false)
    } catch (error: SecurityException) {
      result.error("language_permission_denied", error.message, null)
    }
  }

  private fun processTextIntent(text: String): Intent =
    Intent(Intent.ACTION_PROCESS_TEXT).apply {
      type = TEXT_MIME_TYPE
      putExtra(Intent.EXTRA_PROCESS_TEXT, text)
      putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
    }

  private fun queryLanguageHandlers(
    intent: Intent,
    browserPackages: Set<String>,
  ): List<ComponentName> = packageManager
    .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
    .map { info ->
      ComponentName(info.activityInfo.packageName, info.activityInfo.name)
    }
    .filter { component ->
      component.packageName != packageName && component.packageName !in browserPackages
    }
    .distinct()

  private fun browserPackages(): Set<String> = packageManager
    .queryIntentActivities(
      Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")),
      PackageManager.MATCH_DEFAULT_ONLY,
    )
    .map { info -> info.activityInfo.packageName }
    .toSet()

  private fun browserComponents(): Set<ComponentName> = packageManager
    .queryIntentActivities(
      Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")),
      PackageManager.MATCH_DEFAULT_ONLY,
    )
    .map { info ->
      ComponentName(info.activityInfo.packageName, info.activityInfo.name)
    }
    .toSet()

  private fun installApk(call: MethodCall, result: MethodChannel.Result) {
    val path = call.argument<String>("path")
    if (path.isNullOrBlank()) {
      result.error("invalid_apk_path", "安装包路径无效", null)
      return
    }

    val file = File(path)
    if (!file.isFile) {
      result.error("apk_not_found", "安装包不存在", null)
      return
    }

    val uri = try {
      FileProvider.getUriForFile(
        this,
        "$packageName$UPDATE_FILE_PROVIDER_SUFFIX",
        file,
      )
    } catch (_: IllegalArgumentException) {
      result.error("apk_share_failed", "无法读取安装包", null)
      return
    }

    val intent = Intent(Intent.ACTION_VIEW).apply {
      setDataAndType(uri, APK_MIME_TYPE)
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    try {
      startActivity(intent)
      result.success(null)
    } catch (_: ActivityNotFoundException) {
      result.error("installer_not_found", "系统中没有可用的安装程序", null)
    } catch (_: SecurityException) {
      result.error("install_permission_denied", "请允许开卷安装应用", null)
    }
  }

  companion object {
    private const val CHANNEL = "com.kaijuan.reader/clipboard"
    private const val UPDATE_CHANNEL = "com.kaijuan.reader/system_media"
    private const val LANGUAGE_CHANNEL = "com.kaijuan.reader/language"
    private const val ACTION_DEFINE = "android.intent.action.DEFINE"
    private const val TEXT_MIME_TYPE = "text/plain"
    private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    private const val UPDATE_FILE_PROVIDER_SUFFIX = ".update_file_provider"
  }
}
