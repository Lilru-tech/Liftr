package com.lilru.liftr.ui.pets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

fun petRarityColor(rarity: String): Color = when (rarity.lowercase()) {
    "common" -> Color(0xFF9CA3AF)
    "uncommon" -> Color(0xFF22C55E)
    "rare" -> Color(0xFF3B82F6)
    "epic" -> Color(0xFFA855F7)
    "legendary" -> Color(0xFFEF4444)
    "mythic" -> Color(0xFFF59E0B)
    else -> Color(0xFF9CA3AF)
}

fun petRarityLabel(rarity: String): String = rarity.replaceFirstChar { it.uppercase() }

@Composable
fun PetRarityBadge(rarity: String, modifier: Modifier = Modifier) {
    val color = petRarityColor(rarity)
    Text(
        text = petRarityLabel(rarity),
        modifier = modifier
            .background(color.copy(alpha = 0.2f), RoundedCornerShape(50))
            .border(1.dp, color.copy(alpha = 0.6f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp),
        color = color,
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold
    )
}
