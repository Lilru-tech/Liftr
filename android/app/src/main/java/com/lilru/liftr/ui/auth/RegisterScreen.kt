package com.lilru.liftr.ui.auth

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.safeDrawing
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

private val IosActionBlue = Color(0xFF007AFF)

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

@OptIn(ExperimentalMaterial3Api::class)
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
    var sexMenuExpanded by remember { mutableStateOf(false) }
    var includeDob by rememberSaveable { mutableStateOf(false) }
    var dobMillis by remember { mutableStateOf<Long?>(null) }
    var showDobPicker by remember { mutableStateOf(false) }
    var height by rememberSaveable { mutableStateOf("") }
    var weight by rememberSaveable { mutableStateOf("") }
    var usernameDirty by rememberSaveable { mutableStateOf(false) }
    var triedSubmit by rememberSaveable { mutableStateOf(false) }

    val uiError = viewModel.uiError.collectAsStateWithLifecycle().value
    val busy = viewModel.busy.collectAsStateWithLifecycle().value

    val defaultDobMillis = remember {
        val cal = java.util.Calendar.getInstance()
        cal.add(java.util.Calendar.YEAR, -20)
        cal.timeInMillis
    }

    val emailValid = email.isEmpty() || emailPattern.matches(email)
    val passValid = password.isEmpty() || password.length >= 8
    val userTrim = username.trim()
    val isUsernameValid = userTrim.length >= 3
    val formOk = email.isNotEmpty() && emailPattern.matches(email) &&
        password.length >= 8 && isUsernameValid
    val canSubmit = formOk && !busy

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

    val sexLabel = stringResource(
        sexOptions.find { it.wire == sexWire }?.labelRes ?: R.string.auth_sex_prefer_not
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .liftrAppBackgroundGradient(LiftrPreferences.backgroundTheme(appContext))
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.auth_back))
                }
            }
            Text(
                stringResource(R.string.auth_register_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(16.dp))
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.88f),
                border = BorderStroke(0.8.dp, Color.White.copy(alpha = 0.22f)),
                shadowElevation = 6.dp
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
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
                        isError = !emailValid && email.isNotEmpty(),
                        supportingText = {
                            if (!emailValid && email.isNotEmpty()) {
                                Text(stringResource(R.string.auth_email_invalid))
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
                        isError = !passValid && password.isNotEmpty(),
                        supportingText = {
                            if (!passValid && password.isNotEmpty()) {
                                Text(stringResource(R.string.auth_validation_password_short))
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = username,
                        onValueChange = {
                            username = it
                            usernameDirty = true
                            viewModel.clearUiError()
                        },
                        label = { Text(stringResource(R.string.auth_username)) },
                        singleLine = true,
                        isError = (usernameDirty || triedSubmit) && (!isUsernameValid || userTrim.isEmpty()),
                        supportingText = {
                            if ((usernameDirty || triedSubmit) && userTrim.isEmpty()) {
                                Text(stringResource(R.string.auth_validation_username_required))
                            } else if ((usernameDirty || triedSubmit) && !isUsernameValid) {
                                Text(stringResource(R.string.auth_validation_username_short))
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    )
                    HorizontalDivider(Modifier.padding(vertical = 4.dp))
                    ExposedDropdownMenuBox(
                        expanded = sexMenuExpanded,
                        onExpandedChange = { sexMenuExpanded = it }
                    ) {
                        OutlinedTextField(
                            value = sexLabel,
                            onValueChange = {},
                            readOnly = true,
                            singleLine = true,
                            label = { Text(stringResource(R.string.auth_register_sex)) },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = sexMenuExpanded) },
                            modifier = Modifier
                                .menuAnchor(type = MenuAnchorType.PrimaryNotEditable, enabled = true)
                                .fillMaxWidth()
                        )
                        ExposedDropdownMenu(
                            expanded = sexMenuExpanded,
                            onDismissRequest = { sexMenuExpanded = false }
                        ) {
                            sexOptions.forEach { opt ->
                                DropdownMenuItem(
                                    text = { Text(stringResource(opt.labelRes)) },
                                    onClick = {
                                        sexWire = opt.wire
                                        sexMenuExpanded = false
                                    }
                                )
                            }
                        }
                    }
                    RowToggle(
                        label = stringResource(R.string.auth_register_include_dob),
                        checked = includeDob,
                        onCheckedChange = { includeDob = it }
                    )
                    if (includeDob) {
                        Text(
                            stringResource(R.string.auth_register_dob),
                            style = MaterialTheme.typography.labelMedium
                        )
                        TextButton(onClick = { showDobPicker = true }, modifier = Modifier.fillMaxWidth()) {
                            Text(dobLabel ?: stringResource(R.string.auth_register_pick_dob))
                        }
                    }
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
                    Spacer(Modifier.height(4.dp))
                    Text(
                        stringResource(R.string.auth_register_footnote_bottom),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Button(
                        onClick = {
                            triedSubmit = true
                            if (!formOk) return@Button
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
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(48.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = IosActionBlue,
                            contentColor = Color.White,
                            disabledContainerColor = Color.Gray.copy(alpha = 0.5f)
                        )
                    ) {
                        Text(
                            if (busy) {
                                stringResource(R.string.auth_creating)
                            } else {
                                stringResource(R.string.auth_create_account_btn)
                            },
                            style = MaterialTheme.typography.labelLarge
                        )
                    }
                }
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
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .weight(1f)
                .padding(end = 8.dp)
        )
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedTrackColor = IosActionBlue.copy(alpha = 0.45f),
                checkedThumbColor = Color.White,
                checkedBorderColor = IosActionBlue
            )
        )
    }
}

private fun formatDobForDisplay(millis: Long): String {
    val z = ZoneId.systemDefault()
    return Instant.ofEpochMilli(millis).atZone(z).toLocalDate().format(
        DateTimeFormatter.ofPattern("d MMM yyyy", Locale.getDefault())
    )
}
