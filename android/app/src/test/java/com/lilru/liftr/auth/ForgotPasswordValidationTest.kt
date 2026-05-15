package com.lilru.liftr.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ForgotPasswordValidationTest {
    @Test
    fun authRedirectURL() {
        assertEquals("com.lilru.liftr", AuthRedirect.SCHEME)
        assertEquals("auth-callback", AuthRedirect.HOST)
        assertEquals("com.lilru.liftr://auth-callback", AuthRedirect.APP_DEEP_LINK_URL)
        assertEquals(
            "https://settleit-auth.vercel.app/auth/callback",
            AuthRedirect.WEB_CALLBACK_URL
        )
    }

    @Test
    fun isAuthCallback() {
        assertTrue(
            AuthRedirect.isAuthCallback(
                android.net.Uri.parse("com.lilru.liftr://auth-callback?code=test")
            )
        )
        assertFalse(AuthRedirect.isAuthCallback(android.net.Uri.parse("https://example.com")))
    }

    @Test
    fun passwordValidation() {
        assertFalse(PasswordResetValidation.isPasswordValid("short"))
        assertTrue(PasswordResetValidation.isPasswordValid("longenough"))
        assertTrue(PasswordResetValidation.passwordsMatch("abc", "abc"))
        assertFalse(PasswordResetValidation.passwordsMatch("abc", "xyz"))
    }
}
