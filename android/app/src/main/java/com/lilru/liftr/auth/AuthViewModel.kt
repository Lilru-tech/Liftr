package com.lilru.liftr.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.lilru.liftr.data.BackendContracts
import com.lilru.liftr.push.FcmTokenUploader
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.SignOutScope
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.auth.user.UserInfo
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.SupabaseClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.ZoneId

class AuthViewModel(
    private val supabase: SupabaseClient
) : ViewModel() {
    val sessionStatus: StateFlow<SessionStatus> = supabase.auth.sessionStatus

    private val _uiError = MutableStateFlow<String?>(null)
    val uiError: StateFlow<String?> = _uiError.asStateFlow()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    fun clearUiError() {
        _uiError.value = null
    }

    /**
     * @param onSignInSuccess Llamada solo si el inicio de sesión no lanza; para persistir email / banner.
     */
    fun signIn(
        email: String,
        password: String,
        onSignInSuccess: () -> Unit = {}
    ) {
        viewModelScope.launch {
            _busy.value = true
            _uiError.value = null
            try {
                supabase.auth.signInWith(Email) {
                    this.email = email
                    this.password = password
                }
                onSignInSuccess()
            } catch (e: Exception) {
                _uiError.value = e.message?.take(300) ?: e::class.java.simpleName
            } finally {
                _busy.value = false
            }
        }
    }

    /**
     * Flujo alineado con RegisterView (iOS): RPC `precheck_signup` + registro con metadata + `profiles` upsert.
     */
    @Suppress("LongParameterList")
    fun signUp(
        email: String,
        password: String,
        username: String,
        /** male | female | other | prefer_not_to_say (mismo wire que [Liftr.RegisterView] Sex) */
        sex: String,
        includeDateOfBirth: Boolean,
        dateOfBirthMillis: Long?,
        heightCmText: String,
        weightKgText: String,
        onEmailConfirmation: () -> Unit
    ) {
        viewModelScope.launch {
            _busy.value = true
            _uiError.value = null
            val clean = username.trim()
            if (clean.length < 3) {
                _uiError.value = "Username must be at least 3 characters."
                _busy.value = false
                return@launch
            }
            if (password.length < 8) {
                _uiError.value = "Password must be at least 8 characters."
                _busy.value = false
                return@launch
            }
            val dobYmd = if (includeDateOfBirth && dateOfBirthMillis != null) {
                millisToYyyyMmDdLocal(dateOfBirthMillis)
            } else {
                null
            }
            val height = parseRegisterDouble(heightCmText)
            val weight = parseRegisterDouble(weightKgText)
            val meta = signUpUserMetadataJson(
                cleanUsername = clean,
                sex = sex,
                dateOfBirthYyyyMmDd = dobYmd,
                heightCm = height,
                weightKg = weight
            )
            try {
                val pre = runPrecheck(email, clean)
                if (pre != null) {
                    if (pre.emailExists) {
                        _uiError.value = "Email is already registered."
                        return@launch
                    }
                    if (pre.usernameExists) {
                        _uiError.value = "Username is already taken."
                        return@launch
                    }
                }
                supabase.auth.signUpWith(Email) {
                    this.email = email
                    this.password = password
                    data = meta
                }
                val user = supabase.auth.currentUserOrNull()
                if (user == null) {
                    onEmailConfirmation()
                    return@launch
                }
                upsertProfileForUser(
                    user = user,
                    cleanUsername = clean,
                    sex = sex,
                    dateOfBirthYyyyMmDd = dobYmd,
                    heightCm = height,
                    weightKg = weight
                )
            } catch (e: Exception) {
                _uiError.value = mapSignUpError(e)
            } finally {
                _busy.value = false
            }
        }
    }

    @Serializable
    private data class PrecheckRow(
        @SerialName("email_exists") val emailExists: Boolean,
        @SerialName("username_exists") val usernameExists: Boolean
    )

    private data class Precheck(
        val emailExists: Boolean,
        val usernameExists: Boolean
    )

    private val json = Json { ignoreUnknownKeys = true }

    private suspend fun runPrecheck(email: String, username: String): Precheck? =
        runCatching {
            val res = supabase.postgrest.rpc(
                BackendContracts.Rpc.PRECHECK_SIGNUP,
                buildJsonObject {
                    put("p_email", email)
                    put("p_username", username)
                }
            ) { }
            val text = res.data
            val list = json.decodeFromString<List<PrecheckRow>>(text)
            val r = list.firstOrNull() ?: return@runCatching null
            Precheck(
                emailExists = r.emailExists,
                usernameExists = r.usernameExists
            )
        }.getOrNull()

    private fun mapSignUpError(e: Exception): String {
        val raw = e.message ?: e.toString()
        val low = raw.lowercase()
        if ("already" in low || "exists" in low) return "Email is already registered."
        if ("password" in low && "length" in low) return "Password must be at least 8 characters."
        return raw.take(300)
    }

    private fun signUpUserMetadataJson(
        cleanUsername: String,
        sex: String,
        dateOfBirthYyyyMmDd: String?,
        heightCm: Double?,
        weightKg: Double?
    ) = buildJsonObject {
        put("username", JsonPrimitive(cleanUsername))
        put("sex", JsonPrimitive(sex))
        dateOfBirthYyyyMmDd?.let { put("date_of_birth", JsonPrimitive(it)) }
        heightCm?.let { put("height_cm", JsonPrimitive(it)) }
        weightKg?.let { put("weight_kg", JsonPrimitive(it)) }
    }

    private suspend fun upsertProfileForUser(
        user: UserInfo,
        cleanUsername: String,
        sex: String,
        dateOfBirthYyyyMmDd: String?,
        heightCm: Double?,
        weightKg: Double?
    ) {
        runCatching {
            supabase.from(BackendContracts.Tables.PROFILES).upsert(
                buildJsonObject {
                    put("user_id", JsonPrimitive(user.id))
                    put("username", JsonPrimitive(cleanUsername))
                    put("sex", JsonPrimitive(sex))
                    if (dateOfBirthYyyyMmDd != null) {
                        put("date_of_birth", JsonPrimitive(dateOfBirthYyyyMmDd))
                    } else {
                        put("date_of_birth", JsonNull)
                    }
                    if (heightCm != null) {
                        put("height_cm", JsonPrimitive(heightCm))
                    } else {
                        put("height_cm", JsonNull)
                    }
                    if (weightKg != null) {
                        put("weight_kg", JsonPrimitive(weightKg))
                    } else {
                        put("weight_kg", JsonNull)
                    }
                }
            ) {
                onConflict = "user_id"
            }
        }
    }

    private fun parseRegisterDouble(s: String): Double? {
        val t = s.trim().replace(',', '.')
        if (t.isEmpty()) return null
        return t.toDoubleOrNull()
    }

    private fun millisToYyyyMmDdLocal(millis: Long): String =
        Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate().toString()

    fun signOut() {
        viewModelScope.launch {
            _uiError.value = null
            runCatching { FcmTokenUploader.clearFcmToken(supabase) }
            runCatching {
                supabase.auth.signOut(SignOutScope.GLOBAL)
            }
        }
    }
}

class AuthViewModelFactory(
    private val supabase: SupabaseClient
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass != AuthViewModel::class.java) {
            error("Unknown ViewModel: ${modelClass.name}")
        }
        return AuthViewModel(supabase) as T
    }
}
