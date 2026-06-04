# Checklist QA manual: Add + detalle + activos (iOS ↔ Android)

Objetivo: validar **comportamiento y datos** entre un build **iOS** (referencia) y **Android**, en el subconjunto **Añadir entreno**, **Detalle de entreno** y **Entrenos activos** (fuerza, cardio, sport).

**Prerrequisitos**

- Mismo entorno Supabase / mismas credenciales de prueba en ambos dispositivos o simuladores.
- Anotar **versión de build** y **commit** en cada pasada de QA.
- Para pruebas de **anuncios** o **premium**, usar la misma cuenta o flag de prueba que en iOS.

**Referencias de código (para dudas o bugs)**

| Área | iOS (Swift) | Android (Kotlin) |
|------|-------------|------------------|
| Añadir | `Liftr/AddWorkoutSheet.swift`, `WorkoutRecommendationFlowView.swift`, `WorkoutRecommendationService.swift` | `ui/add/AddWorkoutTabScreen.kt`, `AddWorkoutViewModel.kt`, `recommendation/*`, `AddWorkoutRecommendationDialog.kt` |
| Detalle | `Liftr/WorkoutDetailView.swift`, `EditWorkoutMetaSheet.swift`, `CommentView.swift` | `ui/home/WorkoutDetailScreen.kt`, `WorkoutDetailViewModel.kt`, `Edit*WorkoutMetaSheetContent.kt` |
| Cuenta atrás | `Liftr/StartWorkoutCountdownView.swift` | `ui/home/StartWorkoutCountdownScreen.kt`, `prefs/LiftrPreferences.kt` (`skipStartCountdown`) |
| Activos | `ActiveStrengthWorkoutView.swift`, `ActiveCardioWorkoutView.swift`, `ActiveSportWorkoutView.swift` | `ui/active/ActiveStrengthWorkoutScreen.kt`, `ActiveCardioWorkoutScreen.kt`, `ActiveSportWorkoutScreen.kt` + `*ViewModel.kt` |
| Ayuda Add | `WorkoutHelpSheet` (iOS) | `ui/add/WorkoutHelpScreen.kt` (`WorkoutHelpSheetContent`) |
| Fuerza avanzada | `StrengthSetRowEditor.swift`, `StrengthRoutineOverwrite.swift` | `ui/add/StrengthExerciseDraftsEditorBlock.kt`, `ui/add/StrengthRoutineOverwrite.kt`, `ui/active/ActiveStrengthWorkoutViewModel.kt` |

Paridad Add detallada (RPC, planned, competición, comentarios): [`android/ADD_WORKOUT_PARITY.md`](../android/ADD_WORKOUT_PARITY.md).

---

## A. Pestaña / flujo Add

### A1. Modo y tipo

- [ ] **Add** vs **Plan**: al guardar, el entreno aparece como publicado o **planned** y en Home el chip **My planned** (Android) coincide con lo que ves en iOS para el mismo flujo.
- [ ] Cambio de tipo **Strength / Cardio / Sport**: no se pierden datos críticos al volver (comportamiento razonable alineado con iOS).
- [ ] **Título, notas, fechas, intensidad percibida** (donde aplique): mismos valores visibles en detalle tras crear.

### A2. Fuerza

- [ ] Añadir ejercicios, series, reps, peso, RPE/notas si aplica: el detalle y el activo reflejan lo guardado.
- [ ] **Rutinas y carpetas** (sheet de rutinas): crear, aplicar, reemplazar con confirmación; persistencia de carpetas plegadas tras cerrar app (Android: `StrengthRoutinesSheetPreferences`).
- [ ] **Previsualización de rutina**: tocar una rutina abre detalle/previsualización; aplicar, editar, duplicar y borrar desde esa superficie no corrompe el borrador actual.
- [ ] **Overwrite de rutina**: crear o terminar un entreno desde una rutina, cambiar reps/peso/descanso/RPE/notas o pasos de drop set, y confirmar que la hoja “Review changes” muestra diferencias antes de actualizar la plantilla. Probar también “Not now” y verificar que el entrenamiento queda guardado.
- [ ] **Drop set**: convertir una serie normal en drop set con 2+ pasos, añadir/quitar paso, limpiar drop, guardar y reabrir en iOS y Android. El detalle debe mostrar todos los pasos y la BD debe conservar `weight_segments`.
- [ ] **Grupo / varias personas / same session vs per person**: mismos resultados en número de entrenos vinculados y participantes que en iOS (ver ayuda y strings de *linked* en `ADD_WORKOUT_PARITY.md`).

### A3. Cardio

- [ ] Actividad, duración y campos específicos: payload coherente; en detalle se lee igual que en iOS.
- [ ] Si usas **competición** al crear: mismo criterio de inscripción que en iOS (y documentar la divergencia **Publish** en detalle descrita en `ADD_WORKOUT_PARITY.md`).

### A4. Sport / Hyrox

- [ ] Deporte, resultado, stats (fútbol, basket, etc.): validar un deporte “complejo” y uno simple.
- [ ] **Hyrox**: ejercicios, nombres mostrados, payload; comparar con iOS en un caso con varios bloques.

### A5. Recomendaciones y ayuda

- [ ] Abrir **recomendaciones** (fuerza/cardio/sport según UI): el flujo termina aplicando borrador o cancelando sin corromper el formulario.
- [ ] **Ayuda** (`WorkoutHelpSheetContent`): secciones que esperas en iOS cubiertas o explícitamente reducidas (anotar gap).

### A6. Preferencias y UX

- [ ] **Idioma de nombres de ejercicios** (DataStore / picker): cambia la fuente de nombres en el picker como en iOS.
- [ ] Tras **duplicar desde detalle** (si pruebas Add en cadena): el borrador llega al tab Add con los campos esperados.

---

## B. Detalle de entreno (`WorkoutDetailScreen`)

### B1. Carga y permisos

- [ ] Abrir un entreno propio, de otro usuario, y **planned** como participante: botones **Edit / Start / Duplicate / Publish** según reglas (dueño vs participante), alineado con iOS.
- [ ] Estados de carga y error: mensaje usable y reintento.

### B2. Social

- [ ] **Like** y contador; lista de **likers** (sheet).
- [ ] **Comentarios**: publicar raíz, respuesta, me gusta en comentario, cargar más si hay muchos, borrado (si aplica).

### B3. Acciones de dueño / flujo planned

- [ ] **Editar metadatos** (fuerza/cardio/sport): guardar y ver reflejo en lista y detalle; casos con sesión cardio/sport y solo `workouts` (ver `ADD_WORKOUT_PARITY.md`). En fuerza, incluir una serie normal y una con `weight_segments` para confirmar que no se pierde el drop set al guardar.
- [ ] **Publicar** planned: pasa a publicado; anotar comportamiento de **competición en Android** vs iOS (tabla en doc de paridad).
- [ ] **Eliminar** (confirmación, desaparece del feed).

### B4. Duplicar y comparar

- [ ] **Duplicar** → abre Add con borrador; publicar y verificar integridad.
- [ ] **Comparar con otro entreno**: flujo completo hasta pantalla de comparación y datos mostrados.

### B5. Inicio del activo

- [ ] **Start** con cuenta atrás: se muestra `StartWorkoutCountdownScreen` y luego la pantalla activa correcta.
- [ ] Con **omitir cuenta atrás** activado en perfil (`skipStartCountdown`): entra directo al activo (mismo interruptor que uses en iOS si existe equivalente, o solo Android).
- [ ] **Fuerza con participantes**: diálogo dual / enlace al entreno invitado; **solo / dual** coherente con iOS.
- [ ] **Cardio / Sport**: Start abre el activo correspondiente.

### B6. Mapa y multimedia (si aplica al entreno)

- [ ] Ruta o mapa en cardio: se renderiza y centra; coherencia con iOS en el mismo `workoutId`.

---

## C. Entrenos activos

### C1. Fuerza (`ActiveStrengthWorkoutScreen`)

- [ ] Temporizador / navegación entre ejercicios; completar series; **finalizar** y ver entreno terminado en detalle.
- [ ] **Pista de navegación** (banner la primera vez): se muestra o se respeta “ya visto”, según producto.
- [ ] **Drop set en activo**: convertir una serie durante el entreno, editar pasos, completar, finalizar y reabrir detalle. Verificar que el primer paso se usa como resumen de reps/peso y que todos los pasos se guardan en `weight_segments`.
- [ ] **Rutina actualizada desde activo**: si el entreno viene de una rutina, cambiar la prescripción durante el activo y validar que el prompt de overwrite aparece solo cuando hay diferencias serializables.
- [ ] Modo **dual** (si lo probaste): UI de dos entrenos enlazados y cierre sin datos corruptos.

### C2. Cardio (`ActiveCardioWorkoutScreen`)

- [ ] Inicio de tracking; **splits** o métricas en vivo alineadas con expectativa iOS.
- [ ] **FGS / notificación** de entreno en curso: al volver desde launcher, sigue el estado correcto.
- [ ] Finalizar: duración, distancia, notas (incl. apéndice GPS si aplica en vuestro flujo).

### C3. Sport (`ActiveSportWorkoutScreen`)

- [ ] Resultado del partido / stats; finalizar y reflejo en detalle (incl. `match_result` normalizado).

---

## D. Divergencias conocidas (no marcar como fallo sin criterio)

- **Live Activity (iOS)** vs **FGS + notificación + widget (Android)**: comparar **intención** (entreno en curso visible), no pixel-paridad.
- **Publicar planned + competición**: Android puede llamar a `submit_workout_to_competition` al publicar; iOS hoy no en esa acción — ver `ADD_WORKOUT_PARITY.md`.
- **Import salud**: HealthKit vs Health Connect son flujos distintos; fuera de este checklist salvo que el caso de prueba sea import → detalle.

---

## E. Cierre de sesión QA

- [ ] Lista de **fallos** con: pasos, plataforma, `workoutId` si aplica, captura o logcat (`tag` relevante en Android).
- [ ] **OK parcial**: anotar qué secciones (A/B/C) quedaron validadas y en qué build.
