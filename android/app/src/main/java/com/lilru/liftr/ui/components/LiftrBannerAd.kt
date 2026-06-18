package com.lilru.liftr.ui.components

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.util.Log
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.LoadAdError
import com.lilru.liftr.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val TAG = "LiftrBannerAd"
private const val MAX_LOAD_ATTEMPTS = 3

private fun Context.findActivity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}

@Composable
fun LiftrBannerAd(
    modifier: Modifier = Modifier,
    horizontalPadding: Dp = 12.dp,
    verticalPadding: Dp = 4.dp
) {
    val context = LocalContext.current
    val adContext = remember(context) { context.findActivity() ?: context }
    var failed by remember { mutableStateOf(false) }
    val loadAttempts = remember { intArrayOf(0) }

    if (failed) return

    AndroidView(
        modifier = modifier
            .fillMaxWidth()
            .height(50.dp)
            .padding(horizontal = horizontalPadding, vertical = verticalPadding),
        factory = {
            AdView(adContext).apply {
                setAdSize(AdSize.BANNER)
                adUnitId = BuildConfig.AD_BANNER_UNIT_ID
                adListener = object : AdListener() {
                    override fun onAdFailedToLoad(error: LoadAdError) {
                        Log.w(TAG, "load failed attempt=${loadAttempts[0] + 1} code=${error.code} ${error.message}")
                        loadAttempts[0]++
                        if (loadAttempts[0] >= MAX_LOAD_ATTEMPTS) {
                            failed = true
                        } else {
                            CoroutineScope(Dispatchers.Main).launch {
                                delay(600L * loadAttempts[0])
                                loadAd(AdRequest.Builder().build())
                            }
                        }
                    }
                }
                loadAttempts[0] = 1
                loadAd(AdRequest.Builder().build())
            }
        },
        update = { view ->
            if (!failed && view.adUnitId.isNullOrBlank()) {
                view.adUnitId = BuildConfig.AD_BANNER_UNIT_ID
                view.setAdSize(AdSize.BANNER)
                loadAttempts[0] = 1
                view.loadAd(AdRequest.Builder().build())
            }
        },
        onRelease = { view ->
            view.destroy()
        }
    )
}
