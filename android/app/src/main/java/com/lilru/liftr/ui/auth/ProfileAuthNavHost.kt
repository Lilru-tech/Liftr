package com.lilru.liftr.ui.auth

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.lilru.liftr.auth.AuthViewModel

@Composable
fun ProfileAuthNavHost(
    viewModel: AuthViewModel,
    modifier: Modifier = Modifier
) {
    val navController = rememberNavController()
    NavHost(
        navController = navController,
        startDestination = "auth_login",
        modifier = modifier
    ) {
        composable("auth_login") {
            LoginScreen(
                viewModel = viewModel,
                onNavigateToRegister = {
                    navController.navigate("auth_register") {
                        launchSingleTop = true
                    }
                }
            )
        }
        composable("auth_register") {
            RegisterScreen(
                viewModel = viewModel,
                onBack = { navController.popBackStack() }
            )
        }
    }
}
