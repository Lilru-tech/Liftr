package com.lilru.liftr.ui.feature

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient

@Composable
fun FeatureRequestCreateScreen(
    supabase: SupabaseClient,
    onDismiss: () -> Unit,
    onCreated: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: FeatureRequestCreateViewModel = viewModel(factory = FeatureRequestCreateViewModelFactory(supabase))
    val st by vm.uiState.collectAsStateWithLifecycle()
    val errNo = stringResource(R.string.contact_support_error_no_email)
    val errSignIn = stringResource(R.string.feature_requests_error_sign_in)
    val errGeneric = stringResource(R.string.feature_requests_error_create)

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        LiftrBackTopBar(onBack = onDismiss)
        Text(
            stringResource(R.string.feature_requests_create_title),
            style = MaterialTheme.typography.titleMedium
        )
        if (st.error != null) {
            Text(st.error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        OutlinedTextField(
            value = st.title,
            onValueChange = vm::setTitle,
            label = { Text(stringResource(R.string.feature_requests_field_title)) },
            supportingText = {
                Text(stringResource(R.string.feature_requests_title_count, st.title.length, 50))
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = st.description,
            onValueChange = vm::setDescription,
            label = { Text(stringResource(R.string.feature_requests_field_description)) },
            supportingText = {
                Text(stringResource(R.string.feature_requests_desc_count, st.description.length, 500))
            },
            minLines = 5,
            maxLines = 10,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = st.userEmail,
            onValueChange = { },
            readOnly = true,
            label = { Text(stringResource(R.string.contact_support_your_email)) },
            modifier = Modifier.fillMaxWidth()
        )
        Text(
            stringResource(R.string.contact_support_disclaimer),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Button(
            onClick = {
                vm.create(
                    onSuccess = onCreated,
                    errNoEmail = errNo,
                    errNotSignedIn = errSignIn,
                    errGeneric = errGeneric
                )
            },
            enabled = st.canSave,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                if (st.saving) {
                    stringResource(R.string.feature_requests_saving)
                } else {
                    stringResource(R.string.feature_requests_save)
                }
            )
        }
    }
}
