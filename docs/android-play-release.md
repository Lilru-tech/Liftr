# Release Android: AAB, pistas y Google Play (Liftr)

Complementa [publishing.md §4](publishing.md) con pasos concretos para el módulo `android/`.

## 1. Prerrequisitos locales

- **Android Studio** (Hedgehog+ recomendada) o solo **JDK 17** + el wrapper Gradle del proyecto (`android/gradlew`).
- Cuenta de [Google Play Console](https://play.google.com/console) con la app creada y un **ID de aplicación** que coincida con el `applicationId` en `app/build.gradle.kts` (cambiarlo antes del primer subida si aplica; no se modifica a la ligera en producción).

## 2. Claves y firma (release)

- Generar o importar un **keystore** de publicación. **No** subas el keystore al repositorio: guárdalo de forma segura (gestor de secretos, backup cifrado).
- En `android/` puedes añadir `keystore.properties` (git-ignored) o variables de entorno, y mapear en el `build` de release. El esqueleto inicial deja `minifyEnabled` desactivado; activad **R8/ProGuard** y reglas al estabilizar la app.
- Google recomienda **Play App Signing**: tú subes con una clave de subida, Google firma con la de distribución. Sigue [la guía actual](https://support.google.com/googleplay/android-developer) en el panel de la consola.

## 3. Construir un Android App Bundle (`.aab`)

En la raíz de `android/`:

```bash
./gradlew bundleRelease
```

El AAB se genera en `app/build/outputs/bundle/release/`. En CI, idéntico comando (sin tareas de firma hasta que añadáis signing config).

**Debug (sin publicar):** `./gradlew assembleDebug` (APK) — útil para pistas internas o pruebas manuales.

## 4. Supabase y `local.properties`

Añadid en `android/local.properties` (archivo local, no versionar):

```properties
supabase.url=https://<ref>.supabase.co
supabase.anonKey=<tu-anon-key>
```

Esas claves inyectan `BuildConfig` vía `app/build.gradle.kts` para el cliente. Sin ellas, la app compila y muestra un recordatorio de configuración.

## 5. Pistas de Play (antes de producción)

Orden típico: **prueba interna** → **cerrada** o **abierta** → **producción**, según riesgo y requisitos de vuestro equipo. El portal guía: [crear pistas y lanzamientos](https://support.google.com/googleplay/android-developer/answer/9859152), capturas, ficha, política de datos (salud/fitness, anuncios, etc.).

## 6. Cumplimiento (recordatorio)

- [Target API level mínima](https://developer.android.com/google/play/requirements/target-sdk) de Google Play (actualizad periódicamente en `compileSdk` / `targetSdk`).
- Permisos sensibles (salud, ubicación en segundo plano) desglosados en el formulario de la consola.
- Misma lógica de producto y privacidad coherente con [App Store](https://apps.apple.com/es/app/liftr-workout/id6754026840), adaptada a [política de Google Play](https://play.google.com/about/developer-content-policy/).

## 7. CI (GitHub Actions)

El workflow [`.github/workflows/android.yml`](../.github/workflows/android.yml) compila el módulo con `./gradlew :app:assembleDebug` (no requiere firma). Añadid luego jobs para `bundleRelease` y firma con secretos en el repositorio cuando toque.

## Referencia cruzada

- Decisión de stack: [android-strategy.md](android-strategy.md)
- Paridad de features: [android-parity-inventory.md](android-parity-inventory.md)
- Código: [../android/README.md](../android/README.md)
