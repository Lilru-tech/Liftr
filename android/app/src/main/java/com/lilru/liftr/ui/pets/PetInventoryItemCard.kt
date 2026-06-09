package com.lilru.liftr.ui.pets

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.lilru.liftr.data.PetInventoryWire
import com.lilru.liftr.data.PetMarketItemWire
import com.lilru.liftr.data.PetService

data class PetInventoryDisplayItem(
    val itemType: String,
    val displayName: String,
    val description: String,
    val imagePath: String?,
    val quantity: Int,
    val category: String
) {
    companion object {
        fun from(inventory: PetInventoryWire, catalog: List<PetMarketItemWire>): PetInventoryDisplayItem? {
            if (inventory.quantity <= 0) return null
            val meta = catalog.firstOrNull { it.itemType == inventory.itemType }
            return PetInventoryDisplayItem(
                itemType = inventory.itemType,
                displayName = meta?.displayName ?: inventory.itemType.replace('_', ' ')
                    .replaceFirstChar { it.uppercase() },
                description = meta?.description.orEmpty(),
                imagePath = meta?.imagePath ?: "market/${inventory.itemType}.png",
                quantity = inventory.quantity,
                category = meta?.category ?: PetMarketVisibility.inventoryCategory(inventory.itemType)
            )
        }
    }
}

@Composable
fun PetInventoryItemCard(
    item: PetInventoryDisplayItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier) {
        Surface(
            modifier = Modifier
                .width(100.dp)
                .height(160.dp)
                .clickable(onClick = onClick),
            shape = RoundedCornerShape(12.dp),
            tonalElevation = 2.dp,
            shadowElevation = 2.dp
        ) {
            Column(
                modifier = Modifier.padding(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                AsyncImage(
                    model = PetService.marketImageUrl(item.imagePath),
                    contentDescription = null,
                    modifier = Modifier.size(70.dp)
                )
                Text(
                    text = item.displayName,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.height(32.dp)
                )
                if (item.quantity > 1) {
                    Text(
                        text = "×${item.quantity}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        if (item.quantity > 1) {
            Surface(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp),
                shape = RoundedCornerShape(50),
                color = Color(0xFF007AFF)
            ) {
                Text(
                    text = "${item.quantity}",
                    color = Color.White,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
        }
    }
}
