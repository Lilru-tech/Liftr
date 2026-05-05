package com.lilru.liftr.ui.add

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar

/** Paridad con iOS [WorkoutHelpSheet]. */
@Composable
fun WorkoutHelpSheetContent(
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val scroll = rememberScrollState()
    Column(
        modifier = modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .verticalScroll(scroll)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .padding(bottom = 24.dp)
    ) {
        LiftrBackTopBar(onBack = onClose)
        Text(
            text = stringResource(R.string.workout_help_title),
            style = MaterialTheme.typography.titleLarge
        )
        Spacer(Modifier.height(16.dp))
        Text(
            text = stringResource(R.string.workout_help_how_to_start_headline),
            style = MaterialTheme.typography.titleMedium
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = stringResource(R.string.workout_help_how_to_start_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(16.dp))
        Text(
            text = stringResource(R.string.workout_help_linked_headline),
            style = MaterialTheme.typography.titleMedium
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = stringResource(R.string.workout_help_linked_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(16.dp))
        Text(
            text = stringResource(R.string.workout_help_calories_headline),
            style = MaterialTheme.typography.titleMedium
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = stringResource(R.string.workout_help_calories_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
