package com.lilru.liftr

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.lilru.liftr.ads.UmpHelper
import com.lilru.liftr.bodyweight.HealthConnectBodyWeightSync
import com.lilru.liftr.data.LiftrSupabase
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.navigation.OpenWorkoutIntentStore
import com.lilru.liftr.push.PushIntentStore
import com.lilru.liftr.ui.LiftrAppContent
import com.lilru.liftr.ui.theme.LiftrTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val notificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ -> }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        UmpHelper.requestConsentThenInitAds(this)
        enableEdgeToEdge()
        PushIntentStore.setFromIntent(intent)
        OpenWorkoutIntentStore.setFromIntent(intent)
        askNotificationPermissionIfNeeded()
        setContent {
            LiftrTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val supabase = LiftrSupabase.client
                    if (supabase == null) {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(24.dp),
                            verticalArrangement = Arrangement.Center,
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                text = stringResource(R.string.app_name),
                                style = MaterialTheme.typography.headlineSmall
                            )
                            Text(
                                text = stringResource(R.string.supabase_unconfigured),
                                style = MaterialTheme.typography.bodyLarge,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.padding(top = 12.dp)
                            )
                        }
                    } else {
                        LiftrAppContent(supabase = supabase)
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        val supabase = LiftrSupabase.client ?: return
        if (!LiftrPreferences.bodyWeightHealthSyncEnabled(this)) return
        lifecycleScope.launch {
            runCatching {
                HealthConnectBodyWeightSync(this@MainActivity, supabase).syncRecentSamples()
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        PushIntentStore.setFromIntent(intent)
        OpenWorkoutIntentStore.setFromIntent(intent)
    }

    private fun askNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}
