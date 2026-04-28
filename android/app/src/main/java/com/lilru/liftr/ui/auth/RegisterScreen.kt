package com.lilru.liftr.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.lilru.liftr.R
import com.lilru.liftr.auth.AuthViewModel
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val emailPattern = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\$".toRegex(RegexOption.IGNORE_CASE)

private data class SexWire(
    val wire: String,
    val labelRes: Int
)

private val sexOptions = listOf(
    SexWire("male", R.string.auth_sex_male),
    SexWire("female", R.string.auth_sex_female),
    SexWire("other", R.string.auth_sex_other),
    SexWire("prefer_not_to_say", R.string.auth_sex_prefer_not)
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun RegisterScreen(
    viewModel: AuthViewModel,
    onBack: () -> Unit
) {
    val appContext = LocalContext.current.applicationContext
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var username by rememberSaveable { mutableStateOf("") }
    var showEmailDialog by rememberSaveable { mutableStateOf(false) }
    var sexWire by rememberSaveable { mutableStateOf("prefer_not_to_say") }
    var includeDob by rememberSaveable { mutableStateOf(false) }
    var dobMillis by remember { mutableStateOf<Long?>(null) }
    var showDobPicker by remember { mutableStateOf(false) }
    var height by rememberSaveable { mutableStateOf("") }
    var weight by rememberSaveable { mutableStateOf("") }

    val uiError = viewModel.uiError.collectAsStateWithLifecycle().value
    val busy = viewModel.busy.collectAsStateWithLifecycle().value

    val defaultDobMillis = remember {
        val cal = java.util.Calendar.getInstance()
        cal.add(java.util.Calendar.YEAR, -20)
        cal.timeInMillis
    }

    val emailValid = email.isEmpty() || emailPattern.matches(email)
    val passValid = password.isEmpty() || password.length >= 8
    val userValid = username.trim().isEmpty() || username.trim().length >= 3
    val canSubmit = emailValid && passValid && userValid &&
        email.isNotEmpty() && password.isNotEmpty() && username.trim().isNotEmpty() && !busy

    val dobLabel = when (dobMillis) {
        null -> null
        else -> formatDobForDisplay(dobMillis!!)
    }

    if (showDobPicker) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = dobMillis ?: defaultDobMillis
        )
        DatePickerDialog(
            onDismissRequest = { showDobPicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        state.selectedDateMillis?.let { dobMillis = it }
                        showDobPicker = false
                    }
                ) { Text(stringResource(R.string.auth_ok)) }
            },
            dismissButton = {
                TextButton(onClick = { showDobPicker = false }) {
                    Text(stringResource(R.string.auth_back))
                }
            }
        ) {
            DatePicker(state = state)
        }
    }

    if (showEmailDialog) {
        AlertDialog(
            onDismissRequest = {
                showEmailDialog = false
                onBack()
            },
            title = { Text(stringResource(R.string.auth_check_email_title)) },
            text = { Text(stringResource(R.string.auth_check_email)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showEmailDialog = false
                        onBack()
                    }
                ) {
                    Text(stringResource(R.string.auth_ok))
                }
            }
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .liftrAppBackgroundGradient(LiftrPreferences.backgroundTheme(appContext))
    ) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.Start
    ) {
        Text(
            stringResource(R.string.app_name),
            style = MaterialTheme.typography.headlineSmall
        )
        Text(
            stringResource(R.string.auth_register_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            stringResource(R.string.auth_register_profile_footnote),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (uiError != null) {
            Text(
                uiError,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }
        OutlinedTextField(
            value = email,
            onValueChange = {
                email = it
                viewModel.clearUiError()
            },
            label = { Text(stringResource(R.string.auth_email)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            isError = !emailValid,
            supportingText = {
                if (!emailValid && email.isNotEmpty()) {
                    Text("Invalid email format.", color = MaterialTheme.colorScheme.error)
                }
            },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = password,
            onValueChange = {
                password = it
                viewModel.clearUiError()
            },
            label = { Text(stringResource(R.string.auth_password_min)) },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            isError = !passValid,
            supportingText = {
                if (!passValid && password.isNotEmpty()) {
                    Text("Password must be at least 8 characters.", color = MaterialTheme.colorScheme.error)
                }
            },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = username,
            onValueChange = {
                username = it
                viewModel.clearUiError()
            },
            label = { Text(stringResource(R.string.auth_username)) },
            singleLine = true,
            isError = !userValid,
            supportingText = {
                if (username.isNotEmpty() && username.trim().length < 3) {
                    Text("At least 3 characters.", color = MaterialTheme.colorScheme.error)
                }
            },
            modifier = Modifier.fillMaxWidth()
        )
        HorizontalDivider(Modifier.padding(vertical = 4.dp))
        Text(stringResource(R.string.auth_register_sex), style = MaterialTheme.typography.labelLarge)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            for (opt in sexOptions) {
                FilterChip(
                    selected = sexWire == opt.wire,
                    onClick = { sexWire = opt.wire },
                    label = { Text(stringResource(opt.labelRes)) }
                )
            }
        }
        RowDobAndSwitch(
            includeDob = includeDob,
            onIncludeDobChange = { v -> includeDob = v },
            dobLabel = dobLabel,
            onPickDob = { showDobPicker = true }
        )
        OutlinedTextField(
            value = height,
            onValueChange = { height = it; viewModel.clearUiError() },
            label = { Text(stringResource(R.string.auth_register_height_cm)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = weight,
            onValueChange = { weight = it; viewModel.clearUiError() },
            label = { Text(stringResource(R.string.auth_register_weight_kg)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(8.dp))
        Button(
            onClick = {
                viewModel.signUp(
                    email = email.trim(),
                    password = password,
                    username = username.trim(),
                    sex = sexWire,
                    includeDateOfBirth = includeDob,
                    dateOfBirthMillis = if (includeDob) (dobMillis ?: defaultDobMillis) else null,
                    heightCmText = height,
                    weightKgText = weight
                ) {
                    showEmailDialog = true
                }
            },
            enabled = canSubmit,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                if (busy) {
                    stringResource(R.string.auth_creating)
                } else {
                    stringResource(R.string.auth_create_account_btn)
                }
            )
        }
        TextButton(onClick = onBack) {
            Text(stringResource(R.string.auth_back))
        }
    }
    }
}

@Composable
private fun RowDobAndSwitch(
    includeDob: Boolean,
    onIncludeDobChange: (Boolean) -> Unit,
    dobLabel: String?,
    onPickDob: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
        RowToggle(
            label = stringResource(R.string.auth_register_include_dob),
            checked = includeDob,
            onCheckedChange = onIncludeDobChange
        )
        if (includeDob) {
            Text(
                stringResource(R.string.auth_register_dob),
                style = MaterialTheme.typography.labelMedium
            )
            TextButton(onClick = onPickDob, modifier = Modifier.fillMaxWidth()) {
                Text(dobLabel ?: stringResource(R.string.auth_register_pick_dob))
            }
        }
    }
}

@Composable
private fun RowToggle(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .weight(1f)
                .padding(end = 8.dp)
        )
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

private fun formatDobForDisplay(millis: Long): String {
    val z = ZoneId.systemDefault()
    return Instant.ofEpochMilli(millis).atZone(z).toLocalDate().format(
        DateTimeFormatter.ofPattern("d MMM yyyy", Locale.getDefault())
    )
}
