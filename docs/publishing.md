# Publicación: App Store (iOS) y Google Play (Android)

Este documento aplica a **Liftr**: repositorio con app **iOS** en **Swift** / **SwiftUI** (`Liftr.xcodeproj`), sin módulo Android en el monorepo.

---

## 1. Aclaración: qué implica cada tienda

| Objetivo | Tienda | Plataforma | Qué necesitas hoy (Liftr) |
|----------|--------|------------|----------------------------|
| iPhone / iPad | [App Store](https://www.apple.com/app-store/) | iOS | El proyecto Swift actual. Publicación vía **Xcode** y **App Store Connect**. |
| Móviles Android | [Google Play](https://play.google.com/store) | Android | Un **Android App Bundle (`.aab`)**, generado con **Android** (o un framework que produzca ese artefacto). **No** se publica en Play el binario iOS de Xcode. |

**Conclusión:** Swift compila a **iOS** (y otros targets de Apple, según el proyecto), no a un AAB de Play. Para Play hace falta un **cliente Android** o una **estrategia multiplataforma** que entregue ese artefacto.

**Backend (p. ej. Supabase):** la API y las reglas del servidor suelen reutilizarse; lo que se duplica o reimplementa es la **app en el dispositivo** (UI, SDK nativo, ciclo de vida, etc.).

---

## 2. Si publicas en el App Store (iOS) — aplica a este repo

Resumen de alto nivel (sujeto a la documentación actual de Apple):

1. Cuenta del **Apple Developer Program**.
2. **Identificador de app**, **certificados** y **perfiles** de aprovisionamiento alineados con el bundle ID.
3. En **Xcode**: ajuste de versión/build, firma, **Archive** y subida a **App Store Connect** (o vía `xcodebuild`/`altool`/`notary` según flujo).
4. En **App Store Connect**: ficha, capturas, privacidad, revisión, versiones.
5. Cumplir [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) y requisitos de [privacidad](https://developer.apple.com/app-store/user-privacy-and-data-use/) vigentes.

---

## 3. Si publicas en Google Play — hace falta un camino a Android

Antes de Play Console, el producto necesita un **.aab** creíble. Opciones frecuentes (elige según **equipo**, **plazo** y **gusto de mantenimiento**):

| Enfoque | Resumen | Cuándo encaja |
|---------|---------|---------------|
| **Android nativo (Kotlin o Java)** | App Android de propósito general; misma lógica de producto, **UI y capa móvil** reimplementadas. | Quieres experiencia 100% Android, tienes (o externalizas) desarrollo nativo, y aceptas **dos codebases** (iOS + Android). |
| **Multiplataforma (p. ej. Flutter, React Native)** | Un solo proyecto móvil que genera iOS y Android; con Liftr en Swift, suele implicar **migración o reescritura** hacia el stack elegido, no reutilizar SwiftUI tal cual. | Prioridad es **un solo código** para móviles a medio plazo y aceptas el coste de migración. |
| **Kotlin Multiplatform (KMP) móvil** | Suelen compartirse **lógica** (dominio, red, modelos) entre módulo Kotlin y iOS; las **UIs** siguen siendo **dos** (p. ej. **SwiftUI** + **Jetpack Compose** o Views). | Quieres compartir lógica sin reescribir toda la app, y aceptas seguir invirtiendo en **dos capas de UI**. |

Criterios útiles a la hora de decidir:

- **Plazo a Play:** nativo en paralelo o KMP (dos UIs) suele alinearse a roadmaps de equipo; Flutter/RN a menudo implica fase de migración más larga al inicio, luego un solo móvil.
- **Fidelidad por plataforma:** nativo Android a menudo maximiza adherencia a guías y APIs propias; las soluciones multiplataforma varían en el detalle.
- **Coste de mantenimiento:** dos apps nativas = dos releases; un solo monorepo multiplataforma = otra curva de aprendizaje y de tooling.

Hasta exista un módulo Android o un monorepo multiplataforma en el repositorio, el checklist siguiente es **futuro**, aplicable **cuando ya tengas** un AAB de pruebas o producción.

---

## 4. Checklist Google Play Console (cuando exista un `.aab`)

1. Cuenta de [desarrollador en Google Play](https://play.google.com/console/signup) (alta y políticas vigentes en su portal).
2. **Play Console** → Crear app → Nombre, idioma, tipo (app / juego), gratuito o de pago.
3. **Ficha** de la tienda: descripción, capturas, icono, recursos; cumplir lineamientos de texto e imágenes.
4. **Contenido y privacidad:** cuestionarios (clasificación, objetivo, datos, seguridad) según lo que haga la app.
5. **Firmado:** alinear **keystore** (y, si aplica, **Play App Signing**) con la [documentación actual](https://support.google.com/googleplay/android-developer) de Google.
6. **Pre-lanzamiento:** pistas **interna**, **cerrada** o **abierta** antes de producción, según riesgo y requisitos.
7. **Cumplimiento de políticas:** anuncios, permisos sensibles, salud/fitness si aplica, requisito de [target API level](https://developer.android.com/google/play/requirements/target-sdk) mínimo, etc.
8. Subir el **`.aab`**, completar requisitos pendientes y enviar a **revisión** para producción cuando corresponda.

Enlace de referencia general: [publicar en Google Play](https://support.google.com/googleplay/android-developer/answer/9859152) (puede actualizarse con el tiempo; seguir el portal oficial).

---

## 5. Resumen

- **Liftr en Swift hoy** → vía directa: **App Store (iOS)**.
- **Google Play** → requiere **entrega Android** (nativa, multiplataforma o lógica compartida con KMP + otra UI); luego, **Play Console** y un **AAB** firmado.
