package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.lilru.liftr.data.PetService
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.launch

@Composable
fun FeedFoodOverlay(
    itemType: String,
    ownedQuantity: Int,
    supabase: SupabaseClient,
    onClose: () -> Unit,
    onFeedSuccess: () -> Unit,
    modifier: Modifier = Modifier
) {
    var isFeeding by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val quantityOptions = listOf(1, 5, 10, 25)

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
                model = PetService.marketImageUrl("market/$itemType.png"),
                contentDescription = null,
                modifier = Modifier.height(120.dp)
            )
            Text(
                PetFoodItemType.displayName(itemType),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            Text(
                "Owned: ×$ownedQuantity",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold
            )
            errorMessage?.let {
                Text(it, color = Color.Red, style = MaterialTheme.typography.bodySmall)
            }
            Text("Select quantity", style = MaterialTheme.typography.labelLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                quantityOptions.forEach { qty ->
                    OutlinedButton(
                        onClick = {
                            scope.launch {
                                isFeeding = true
                                errorMessage = null
                                runCatching { PetService.feed(supabase, itemType, qty) }
                                    .onSuccess {
                                        onFeedSuccess()
                                        onClose()
                                    }
                                    .onFailure { e -> errorMessage = e.message }
                                isFeeding = false
                            }
                        },
                        enabled = qty <= ownedQuantity && !isFeeding
                    ) {
                        Text("$qty")
                    }
                }
            }
            if (isFeeding) {
                CircularProgressIndicator()
            }
            TextButton(onClick = onClose) { Text("Close") }
        }
    }
}
