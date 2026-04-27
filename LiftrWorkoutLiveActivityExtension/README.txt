Live Activity (Dynamic Island) — añadir el target de extensión en Xcode
=======================================================================

La app ya incluye ActivityKit y el paquete local `LiftrWorkoutActivityKit`, y arranca/termina la Live Activity desde Fuerza, Cardio y Sport.

Para que la isla y la pantalla de bloqueo muestren la UI hace falta un **Widget Extension** que embeba los archivos de esta carpeta.

1. En Xcode: File → New → Target → **Widget Extension**.
2. Nombre sugerido: `LiftrWorkoutLiveActivity`, desmarca “Include Live Activity” del asistente (o bórralo) y crea el target.
3. Borra el `Widget` / `AppIntent` por defecto del target nuevo.
4. Añade a ese target los archivos de esta carpeta:
   - WorkoutLiveWidget.swift
   - WorkoutLiveActivityViews.swift
   - Info.plist (o copia las claves de NSExtension al Info del target; debe existir `com.apple.widgetkit-extension`).
5. En el target de la extensión: **General → Frameworks** → añade el producto **LiftrWorkoutActivityKit** (mismo paquete local que la app).
6. En el target **Liftr** (app): **Build Phases → Embed Foundation Extensions** (o “Embed App Extensions”) y añade `LiftrWorkoutLiveActivity.appex`.
7. Bundle ID de la extensión: por ejemplo `com.davidgomez.Liftr.LiveActivity` (ajusta a tu equipo).
8. En Ajustes del iPhone: el usuario puede desactivar Live Activities; la app comprueba `ActivityAuthorizationInfo`.

Pulsar la Live Activity abre la app (comportamiento del sistema).
