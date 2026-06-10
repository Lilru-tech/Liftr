package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.lilru.liftr.data.PetFullDataWire
import com.lilru.liftr.data.PetMarketItemWire
import com.lilru.liftr.data.PetService

@Composable
fun RarityUpgradePurchaseOverlay(
    item: PetMarketItemWire,
    petData: PetFullDataWire?,
    balance: Int,
    isBuying: Boolean,
    errorMessage: String?,
    onClose: () -> Unit,
    onConfirm: () -> Unit,
    modifier: Modifier = Modifier
) {
    val rarity = petData?.pet?.rarity
    val next = rarity?.let { PetRarityUpgrade.nextTier(it) }
    val price = rarity?.let { PetRarityUpgrade.upgradeCost(it) } ?: item.price
    val canAfford = price <= balance
    val presentation = PetMarketItemPresentationFactory.make(item, petData)

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp),
        shape = RoundedCornerShape(20.dp),
        tonalElevation = 8.dp
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            AsyncImage(
                model = PetService.marketImageUrl(presentation.imagePath),
                contentDescription = null,
                modifier = Modifier.height(100.dp)
            )

            Text(
                text = PetMarketItemPresentationFactory.modalTitle(item, petData),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )

            if (rarity != null && next != null) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    PetRarityBadge(rarity)
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    PetRarityBadge(next)
                }
            }

            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                tonalElevation = 1.dp
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    if (rarity != null && next != null) {
                        BenefitRow(
                            title = "Stat roll bonus per level",
                            from = PetRarityUpgrade.formattedMultiplier(PetRarityUpgrade.statMultiplier(rarity)),
                            to = PetRarityUpgrade.formattedMultiplier(PetRarityUpgrade.statMultiplier(next))
                        )
                        BenefitRow(
                            title = "Passive coin yield per hour",
                            from = PetRarityUpgrade.formattedMultiplier(PetRarityUpgrade.coinMultiplier(rarity)),
                            to = PetRarityUpgrade.formattedMultiplier(PetRarityUpgrade.coinMultiplier(next))
                        )
                    }
                }
            }

            Text(
                text = "Existing stats are kept. New multipliers apply to future level-ups and coin income only.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Price: $price", fontWeight = FontWeight.SemiBold)
                Icon(Icons.Filled.Paid, contentDescription = null, tint = Color(0xFFFFC107), modifier = Modifier.size(16.dp))
            }
            Text(
                color = if (canAfford) Color(0xFF22C55E) else Color.Red,
                text = if (canAfford) "You can afford this" else "Not enough coins"
            )

            if (errorMessage != null) {
                Text(
                    text = errorMessage,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
            }

            Button(
                onClick = onConfirm,
                enabled = canAfford && !isBuying && rarity != null && next != null,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (isBuying) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp).padding(end = 8.dp))
                }
                Text("Upgrade Rarity")
            }

            TextButton(onClick = onClose) { Text("Close") }
        }
    }
}

@Composable
private fun BenefitRow(title: String, from: String, to: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("${from}×", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Icon(
                Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
                modifier = Modifier.size(12.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text("${to}×", fontWeight = FontWeight.SemiBold)
        }
    }
}
