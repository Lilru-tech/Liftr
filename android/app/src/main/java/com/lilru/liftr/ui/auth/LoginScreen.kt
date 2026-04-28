package com.lilru.liftr.ui.auth

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.lilru.liftr.auth.PostLoginShellMessage
import com.lilru.liftr.prefs.AuthLoginPreferences
import com.lilru.liftr.prefs.LiftrPreferences
import com.lilru.liftr.ui.theme.liftrAppBackgroundGradient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val emailPattern = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\$".toRegex(RegexOption.IGNORE_CASE)

@Composable
fun LoginScreen(
    viewModel: AuthViewModel,
    onNavigateToRegister: () -> Unit
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var rememberMe by remember { mutableStateOf(false) }
    val appContext = LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()
    val welcomeBackText = stringResource(R.string.auth_welcome_back)
    val uiError = viewModel.uiError.collectAsStateWithLifecycle().value
    val busy = viewModel.busy.collectAsStateWithLifecycle().value

    LaunchedEffect(Unit) {
        val s = withContext(Dispatchers.IO) { AuthLoginPreferences.readState(appContext) }
        email = s.savedEmail
        rememberMe = s.rememberEmail
    }

    val emailValid = email.isEmpty() || emailPattern.matches(email)
    val canSubmit = emailValid && email.isNotEmpty() && password.isNotEmpty() && !busy

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
            stringResource(R.string.auth_sign_in_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (uiError != null) {
            Text(
                uiError,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }
        if (!emailValid) {
            Text("Invalid email format.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelSmall)
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
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = password,
            onValueChange = {
                password = it
                viewModel.clearUiError()
            },
            label = { Text(stringResource(R.string.auth_password)) },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth()
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                stringResource(R.string.auth_remember_email),
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier
                    .weight(1f)
                    .padding(end = 8.dp)
            )
            Switch(
                checked = rememberMe,
                onCheckedChange = { rememberMe = it }
            )
        }
        Spacer(Modifier.height(8.dp))
        Button(
            onClick = {
                viewModel.signIn(
                    email = email.trim(),
                    password = password,
                    onSignInSuccess = {
                        PostLoginShellMessage.pending = welcomeBackText
                        scope.launch(Dispatchers.IO) {
                            AuthLoginPreferences.setRememberWithEmail(
                                appContext,
                                rememberMe,
                                email.trim()
                            )
                        }
                    }
                )
            },
            enabled = canSubmit,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                if (busy) {
                    stringResource(R.string.auth_signing_in)
                } else {
                    stringResource(R.string.auth_sign_in)
                }
            )
        }
        TextButton(onClick = onNavigateToRegister) {
            Text(stringResource(R.string.auth_create_account))
        }
    }
    }
}
