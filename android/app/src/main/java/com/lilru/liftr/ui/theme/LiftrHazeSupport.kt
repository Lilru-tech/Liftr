package com.lilru.liftr.ui.theme

import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember

object LiftrHazeSupport {
    fun isBlurSafeOnDevice(): Boolean {
        if (isEmulator()) return false
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    }

    private fun isEmulator(): Boolean {
        return Build.FINGERPRINT.startsWith("generic", ignoreCase = true) ||
            Build.FINGERPRINT.startsWith("unknown", ignoreCase = true) ||
            Build.MODEL.contains("google_sdk", ignoreCase = true) ||
            Build.MODEL.contains("Emulator", ignoreCase = true) ||
            Build.MODEL.contains("Android SDK built for x86", ignoreCase = true) ||
            Build.MANUFACTURER.contains("Genymotion", ignoreCase = true) ||
            Build.HARDWARE.contains("goldfish", ignoreCase = true) ||
            Build.HARDWARE.contains("ranchu", ignoreCase = true) ||
            Build.PRODUCT.contains("sdk", ignoreCase = true)
    }
}

@Composable
fun rememberLiftrHazeBlurEnabled(): Boolean = remember { LiftrHazeSupport.isBlurSafeOnDevice() }
