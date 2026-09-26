package com.reallifecorp.bubblegames

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.util.DisplayMetrics
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Holds a WiFi multicast lock for as long as the app is in front.
 *
 * Without it the WiFi hardware filters out packets not addressed to this
 * device, which silently includes the UDP broadcasts that game discovery is
 * built on: hosting appears to work, joining just never sees anything. Taking
 * the lock costs a little battery, so it is released when the app is not
 * on screen.
 */
class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Draw under the notch too. The app hides the status bar, and with the
        // default cutout mode Android 14 and below then shifts the whole window
        // down below the notch rather than letting it cover the panel. Every
        // layout here is measured against the full panel (getRealMetrics
        // below), so a window 53px short put the bottom edge stripe off the
        // glass and moved every seam by the notch's height. Android 15+ does
        // this by default for apps targeting it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.multidevicesgames/display_metrics",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getPhysicalScreenInfo") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val dm = DisplayMetrics()
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay.getRealMetrics(dm)
                val xdpi = dm.xdpi
                val ydpi = dm.ydpi
                val bucketDpi = dm.densityDpi.toFloat()
                // Trusted only when values are in a plausible phone range and
                // the OEM didn't simply echo the density bucket.
                val trusted = xdpi in 200f..800f &&
                    ydpi in 200f..800f &&
                    kotlin.math.abs(xdpi - bucketDpi) > 5f
                result.success(
                    mapOf(
                        "widthPx" to dm.widthPixels,
                        "heightPx" to dm.heightPixels,
                        "xdpi" to xdpi.toDouble(),
                        "ydpi" to ydpi.toDouble(),
                        "source" to "android_metrics",
                        "trusted" to trusted,
                    )
                )
            } catch (e: Exception) {
                result.error("UNAVAILABLE", e.message, null)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        if (multicastLock != null) return
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("multiscreen-discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            // Discovery degrades to the QR and typed-address paths, which are
            // always on screen. Never worth crashing the app over.
            multicastLock = null
        }
    }

    override fun onStop() {
        try {
            multicastLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            // Nothing useful to do; the lock goes with the process anyway.
        }
        multicastLock = null
        super.onStop()
    }
}
