# Liftr (Android)

Cliente **nativo (Kotlin + Jetpack Compose)** para [Google Play](https://play.google.com/console), en el mismo repositorio que el proyecto iOS.

## Requisitos

- **Android Studio** (o JDK 17+ y el **Android SDK**; `local.properties` debe apuntar al SDK, lo habitual con Android Studio al abrir la carpeta `android/`).
- Estrategia y despliegue: [../docs/android-strategy.md](../docs/android-strategy.md) y [../docs/android-play-release.md](../docs/android-play-release.md).
- Contratos backend (tabla/RPC compartidos con iOS): [../docs/backend-contracts.md](../docs/backend-contracts.md).

## Configuración

1. Copiá o fusioná con `local.properties` a partir de [local.properties.example](local.properties.example):
   - `sdk.dir=…` (Android Studio suele crearlo al abrir el proyecto en esta carpeta).
   - `supabase.url` y `supabase.anonKey` (misma instancia y rol `anon` que en iOS; nunca commitear claves reales).
2. Abrí el directorio `android/` en Android Studio o ejecutá:
   - `./gradlew :app:assembleDebug` — depuración.
   - `./gradlew :app:bundleRelease` — **AAB** para publicación, tras configurar firma de release (véase [android-play-release.md](../docs/android-play-release.md)).

## Código

- [app/src/main/java/com/lilru/liftr/data/LiftrSupabase.kt](app/src/main/java/com/lilru/liftr/data/LiftrSupabase.kt) — inicialización de **Supabase** (análogo conceptual a `Liftr/SupabaseManager.swift`).
- En Android hace falta además el motor **Ktor** `ktor-client-android` (ya declarado en `app/build.gradle.kts`); sin eso, la app puede cerrarse al arrancar.
- **Auth (email/contraseña):** [AuthViewModel](app/src/main/java/com/lilru/liftr/auth/AuthViewModel.kt) + pantallas bajo `ui/auth/`; flujo alineado con iOS (login, registro con `precheck_signup`, fila en `profiles` si hay sesión inmediata). Navegación: [LiftrAppContent.kt](app/src/main/java/com/lilru/liftr/ui/LiftrAppContent.kt).
- `applicationId` y namespace: `com.lilru.liftr`. Cambiarlos con cuidado si el ID en Play Console ya está fijado.

## CI

El workflow [`.github/workflows/android.yml`](../.github/workflows/android.yml) compila el módulo con Gradle en cada cambio bajo `android/`.
