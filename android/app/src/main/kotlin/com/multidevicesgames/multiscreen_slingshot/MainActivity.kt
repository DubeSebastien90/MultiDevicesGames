package com.multidevicesgames.multiscreen_slingshot

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity

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
