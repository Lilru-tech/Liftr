package com.lilru.liftr.ui.pets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar

@Composable
fun PetHelpSheetContent(
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(bottom = 24.dp)
    ) {
        LiftrBackTopBar(onBack = onClose)

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Text(
                text = stringResource(R.string.pet_help_title),
                style = MaterialTheme.typography.titleLarge
            )

            PetHelpHatchingSection()
            PetHelpFoodSection()
            PetHelpTipsSection()
        }
    }
}

@Composable
private fun PetHelpHatchingSection() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = stringResource(R.string.pet_help_hatching_headline),
            style = MaterialTheme.typography.titleMedium
        )
        PetHelpNumberedStep(
            number = 1,
            text = stringResource(R.string.pet_help_hatching_step_buy)
        )
        Row(
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "2.",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.width(20.dp)
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = stringResource(R.string.pet_help_hatching_step_my_items_prefix),
                    style = MaterialTheme.typography.bodyMedium
                )
                Icon(
                    imageVector = Icons.Filled.ShoppingBag,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = stringResource(R.string.pet_help_hatching_step_my_items_suffix),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
        PetHelpNumberedStep(
            number = 3,
            text = stringResource(R.string.pet_help_hatching_step_incubate)
        )
        Text(
            text = stringResource(R.string.pet_help_hatching_note),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun PetHelpFoodSection() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = stringResource(R.string.pet_help_food_headline),
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            text = stringResource(R.string.pet_help_food_intro),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(R.string.pet_help_food_baby), style = MaterialTheme.typography.bodyMedium)
            Text(stringResource(R.string.pet_help_food_kid), style = MaterialTheme.typography.bodyMedium)
            Text(stringResource(R.string.pet_help_food_teen), style = MaterialTheme.typography.bodyMedium)
            Text(stringResource(R.string.pet_help_food_adult), style = MaterialTheme.typography.bodyMedium)
            Text(stringResource(R.string.pet_help_food_elder), style = MaterialTheme.typography.bodyMedium)
        }
        Text(
            text = stringResource(R.string.pet_help_food_note),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun PetHelpTipsSection() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = stringResource(R.string.pet_help_tips_headline),
            style = MaterialTheme.typography.titleMedium
        )
        PetHelpTipCard(
            title = stringResource(R.string.pet_help_tip_reroll_title),
            body = stringResource(R.string.pet_help_tip_reroll_body)
        )
        PetHelpTipCard(
            title = stringResource(R.string.pet_help_tip_rarities_title),
            body = stringResource(R.string.pet_help_tip_rarities_body)
        )
        PetHelpTipCard(
            title = stringResource(R.string.pet_help_tip_evolution_title),
            body = stringResource(R.string.pet_help_tip_evolution_body)
        )
    }
}

@Composable
private fun PetHelpNumberedStep(number: Int, text: String) {
    Row(
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = "$number.",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.width(20.dp)
        )
        Text(text = text, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun PetHelpTipCard(title: String, body: String) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
