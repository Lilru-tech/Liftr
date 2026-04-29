package com.lilru.liftr.ads

import android.app.Activity
import android.util.Log
import com.google.android.gms.ads.MobileAds
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.FormError
import com.google.android.ump.UserMessagingPlatform

/**
 * UMP antes de [MobileAds]; flujo estándar AdMob para EEE/Reino Unido.
 */
object UmpHelper {
    private const val TAG = "Ump"

    fun requestConsentThenInitAds(activity: Activity) {
        val params = ConsentRequestParameters.Builder()
            .setTagForUnderAgeOfConsent(false)
            .build()
        val info = UserMessagingPlatform.getConsentInformation(activity)
        info.requestConsentInfoUpdate(
            activity,
            params,
            {
                UserMessagingPlatform.loadAndShowConsentFormIfRequired(
                    activity
                ) { formError: FormError? ->
                    if (formError != null) {
                        Log.w(TAG, "Form dismiss: ${formError.message}")
                    }
                    MobileAds.initialize(activity) { }
                }
            },
            { requestError: FormError? ->
                Log.w(TAG, "requestConsentInfo: ${requestError?.message}")
                MobileAds.initialize(activity) { }
            }
        )
    }
}
