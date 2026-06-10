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
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import com.lilru.liftr.data.PetEnergyPricing
import com.lilru.liftr.data.PetFullDataWire
import com.lilru.liftr.data.PetMarketItemWire
import com.lilru.liftr.data.PetService
import com.lilru.liftr.ui.pets.PetMarketItemPresentationFactory.modalTitle

@Composable
fun EnergyCapacityUpgradeOverlay(
    item: PetMarketItemWire,
    petData: PetFullDataWire?,
    balance: Int,
    isBuying: Boolean,
    errorMessage: String?,
    onClose: () -> Unit,
    onConfirm: () -> Unit,
    modifier: Modifier = Modifier
) {
    val currentMax = petData?.energy?.max ?: 5
    val nextMax = minOf(currentMax + 1, PetEnergyPricing.MAX_CAPACITY)
    val price = PetEnergyPricing.upgradeCost(currentMax)
    val canAfford = price <= balance
    val atCap = currentMax >= PetEnergyPricing.MAX_CAPACITY
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
                model = PetService.marketImageUrl(presentation.imagePath ?: item.imagePath),
                contentDescription = null,
                modifier = Modifier.size(120.dp)
            )
            Text(modalTitle(item, petData), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                EnergyBadge(currentMax, "Current")
                Text("→")
                EnergyBadge(nextMax, "Next")
            }
            Text(
                "Energy regenerates 1 point every 4 hours up to your max capacity.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Price: $price", fontWeight = FontWeight.SemiBold)
                Icon(Icons.Filled.Paid, contentDescription = null, tint = Color(0xFFFFC107))
            }
            Text(
                if (canAfford) "You can afford this" else "Not enough coins",
                color = if (canAfford) Color(0xFF22C55E) else Color.Red
            )
            errorMessage?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            Button(
                onClick = onConfirm,
                enabled = canAfford && !isBuying && !atCap,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF9800))
            ) {
                if (isBuying) {
                    CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                }
                Text("Expand Capacity")
            }
            TextButton(onClick = onClose) { Text("Close") }
        }
    }
}

@Composable
private fun EnergyBadge(value: Int, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("$value", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    }
}
