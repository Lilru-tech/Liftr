# Autenticación: iOS `ProfileGate` vs Android (Liftr)

## Comportamiento iOS

En [ProfileGate.swift](Liftr/ProfileGate.swift), la pestaña **Perfil** muestra `LoginView` si el usuario no está autenticado, o `ProfileView` si lo está. El resto de la app puede seguir otra política; el “gate” está acotado a **esa pestaña** dentro de `RootView` / `TabView`.

## Comportamiento Android (actual, aceptado en producto)

En [LiftrAppContent.kt](android/app/src/main/java/com/lilru/liftr/ui/LiftrAppContent.kt) el criterio es distinto: mientras `SessionStatus` no sea `Authenticated`, se muestra un **flujo de login/registro a pantalla completa** (`AuthNavHost`); con sesión activa, se monta [MainShellScreen](android/app/src/main/java/com/lilru/liftr/ui/main/MainShellScreen.kt) con todas las pestañas (Home, búsqueda, añadir, ranking, perfil).

- **Ventajas** del enfoque Android: menos estados híbridos, métricas y FCM/Deep links más sencillos, sin tabs “a medias” con datos que requieren login.
- **Diferencia frente a iOS:** no hay “exploración” de tabs con solo la pestaña Perfil pidiendo inicio de sesión; o hay sesión y shell completo, o solo auth.

## Criterio de paridad

No hace falta copiar el gate por pestaña para alcanzar “paridad funcional” (feed, añadir entrenos, perfil) si el producto prioriza un solo punto de entrada de sesión. Si en el futuro se quisiera acercar a iOS, la vía de menor riesgo sería permitir navegación a tabs de solo-lectura con CTAs de login en acciones críticas, o mostrar un login embebido solo al entrar en Perfil — cambio más invasivo (router, RLS, expectativas de notificaciones).

**Estado acordado:** se mantiene el flujo **login global** en Android; esta página documenta la desviación respecto a `ProfileGate` de iOS.
