package com.lilru.liftr.billing

import android.app.Activity
import android.app.Application
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.lilru.liftr.R
import com.lilru.liftr.data.LiftrSupabase
import com.lilru.liftr.data.PremiumStatusStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Paridad aprox. con StoreKit: suscripción [R.string.billing_premium_sku]; entitlement vía servidor.
 */
class PlayBillingManager(private val app: Application) : PurchasesUpdatedListener {
    private val billingScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    var client: BillingClient? = null
        private set
    @Volatile
    var premiumProductDetails: ProductDetails? = null
        private set
    @Volatile
    var lastBillingError: String? = null
        private set

    fun start() {
        if (client != null) return
        val c = BillingClient.newBuilder(app)
            .setListener(this)
            .enablePendingPurchases()
            .build()
        client = c
        c.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    lastBillingError = result.debugMessage
                    Log.w(TAG, "Billing setup: ${result.responseCode} ${result.debugMessage}")
                    return
                }
                lastBillingError = null
                queryProductAndRefreshPurchases()
            }

            override fun onBillingServiceDisconnected() = Unit
        })
    }

    private fun queryProductAndRefreshPurchases() {
        val c = client ?: return
        val productList = listOf(
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(app.getString(R.string.billing_premium_sku))
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        )
        c.queryProductDetailsAsync(
            QueryProductDetailsParams.newBuilder().setProductList(productList).build()
        ) { result, list ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK && !list.isNullOrEmpty()) {
                premiumProductDetails = list[0]
            }
            refreshPremiumFromPlay()
        }
    }

    /** Reconsulta suscripciones activas (p. ej. “Restore” / cambio de dispositivo). */
    fun refreshPremiumFromPlay() {
        val c = client ?: return
        c.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        ) { result, purchases ->
            if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                return@queryPurchasesAsync
            }
            if (purchases != null) {
                for (p in purchases) {
                    if (!p.isAcknowledged && p.purchaseState == Purchase.PurchaseState.PURCHASED) {
                        val ack = AcknowledgePurchaseParams.newBuilder()
                            .setPurchaseToken(p.purchaseToken)
                            .build()
                        c.acknowledgePurchase(ack) { }
                    }
                }
            }
            refreshServerPremium()
        }
    }

    private fun refreshServerPremium() {
        val supabase = LiftrSupabase.client ?: return
        billingScope.launch {
            PremiumStatusStore.refresh(supabase)
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            refreshPremiumFromPlay()
        } else if (result.responseCode != BillingClient.BillingResponseCode.USER_CANCELED) {
            lastBillingError = result.debugMessage
        }
    }

    fun launchSubscriptionFlow(
        activity: Activity,
        onError: (String) -> Unit
    ) {
        val c = client
        val pd = premiumProductDetails
        if (c == null || !c.isReady) {
            onError(activity.getString(R.string.billing_not_ready))
            return
        }
        if (pd == null) {
            queryProductAndRefreshPurchases()
            onError(activity.getString(R.string.billing_product_loading))
            return
        }
        val offer = pd.subscriptionOfferDetails?.firstOrNull()
        val offerToken = offer?.offerToken ?: run {
            onError(activity.getString(R.string.billing_no_offer))
            return
        }
        val p = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(pd)
            .setOfferToken(offerToken)
            .build()
        val flow = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(p))
            .build()
        val r = c.launchBillingFlow(activity, flow)
        if (r.responseCode != BillingClient.BillingResponseCode.OK) {
            onError(r.debugMessage)
        }
    }

    private companion object {
        const val TAG = "PlayBilling"
    }
}
