package com.example.smartads

import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cm.smartads/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAndroidTv" -> result.success(
                        packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                    )
                    "getTvInfo" -> {
                        val metrics = resources.displayMetrics
                        result.success(mapOf(
                            "androidId" to Settings.Secure.getString(
                                contentResolver,
                                Settings.Secure.ANDROID_ID
                            ),
                            "manufacturer" to Build.MANUFACTURER,
                            "brand" to Build.BRAND,
                            "model" to Build.MODEL,
                            "device" to Build.DEVICE,
                            "product" to Build.PRODUCT,
                            "androidVersion" to Build.VERSION.RELEASE,
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "locale" to Locale.getDefault().toLanguageTag(),
                            "timezone" to TimeZone.getDefault().id,
                            "screenWidthPx" to metrics.widthPixels,
                            "screenHeightPx" to metrics.heightPixels,
                            "densityDpi" to metrics.densityDpi
                        ))
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
