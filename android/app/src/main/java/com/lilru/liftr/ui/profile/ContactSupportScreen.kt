package com.lilru.liftr.ui.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lilru.liftr.R
import com.lilru.liftr.ui.components.LiftrBackTopBar
import io.github.jan.supabase.SupabaseClient

@Composable
fun ContactSupportScreen(
    supabase: SupabaseClient,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val vm: ContactSupportViewModel = viewModel(factory = ContactSupportViewModelFactory(supabase))
    val st by vm.uiState.collectAsStateWithLifecycle()
    val subjects = stringArrayResource(R.array.contact_support_subjects).toList()
    var showSubjectPicker by remember { mutableStateOf(false) }
    val subjectIndex = remember(st.subject, subjects) {
        subjects.indexOf(st.subject).takeIf { it >= 0 } ?: 0
    }
    val errNoEmail = stringResource(R.string.contact_support_error_no_email)
    val errSend = stringResource(R.string.contact_support_error_send)
    val emailDisplay = if (st.userEmail.isBlank()) {
        stringResource(R.string.contact_support_email_empty)
    } else {
        st.userEmail
    }

    if (st.success) {
        AlertDialog(
            onDismissRequest = onBack,
            title = { Text(stringResource(R.string.contact_support_success_title)) },
            text = { Text(stringResource(R.string.contact_support_success_body)) },
            confirmButton = {
                TextButton(onClick = onBack) {
                    Text(stringResource(R.string.auth_ok))
                }
            }
        )
        return
    }

    if (showSubjectPicker) {
        AlertDialog(
            onDismissRequest = { showSubjectPicker = false },
            title = { Text(stringResource(R.string.contact_support_subject)) },
            text = {
                LazyColumn(Modifier.heightIn(max = 360.dp)) {
                    itemsIndexed(subjects) { i, subj ->
                        TextButton(
                            onClick = {
                                vm.setSubjectFromList(subjects, i)
                                showSubjectPicker = false
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(subj, modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showSubjectPicker = false }) {
                    Text(stringResource(R.string.auth_back))
                }
            }
        )
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        LiftrBackTopBar(onBack = onBack)
        Text(
            stringResource(R.string.contact_support_intro),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (st.error != null) {
            Text(
                st.error!!,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }
        OutlinedTextField(
            value = emailDisplay,
            onValueChange = {},
            readOnly = true,
            label = { Text(stringResource(R.string.contact_support_your_email)) },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = subjects.getOrElse(subjectIndex) { st.subject },
            onValueChange = {},
            readOnly = true,
            label = { Text(stringResource(R.string.contact_support_subject)) },
            modifier = Modifier
                .fillMaxWidth()
                .clickable { showSubjectPicker = true }
        )
        OutlinedTextField(
            value = st.message,
            onValueChange = vm::setMessage,
            label = { Text(stringResource(R.string.contact_support_message)) },
            placeholder = { Text(stringResource(R.string.contact_support_message_hint)) },
            minLines = 6,
            maxLines = 10,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Sentences
            ),
            supportingText = {
                Text(
                    stringResource(
                        R.string.contact_support_message_count,
                        st.message.length,
                        ContactSupportViewModel.MAX_MESSAGE
                    )
                )
            },
            modifier = Modifier.fillMaxWidth()
        )
        Text(
            stringResource(R.string.contact_support_disclaimer),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Button(
            onClick = {
                vm.send(errorNoEmail = errNoEmail, errorSend = errSend)
            },
            enabled = !st.loading && st.isValid,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                if (st.loading) {
                    stringResource(R.string.contact_support_sending)
                } else {
                    stringResource(R.string.contact_support_send)
                }
            )
        }
    }
}
