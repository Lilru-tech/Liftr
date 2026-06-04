# Auditoría de paridad Add Workout (iOS `AddWorkoutSheet.swift` ↔ Android)

Checklist para ir cerrando huecos; el flujo Android vive en `AddWorkoutTabScreen.kt` / `AddWorkoutViewModel.kt`.

## Modo Add / Plan y feed Home (paridad con `HomeView` / RLS)

- **Add** (`AddWorkoutState.PUBLISHED`): entreno publicado / registro normal → `state` acorde al flujo de creación (p. ej. `published`).
- **Plan** (`AddWorkoutState.PLANNED`): guarda con `state = planned`; esos entrenos **propios** aparecen en el feed principal de Home (misma regla que [HomeView.swift](../../Liftr/HomeView.swift); no hay lista separada “solo planificados” en iOS).
- **Feed Home** ([`HomeViewModel`](app/src/main/java/com/lilru/liftr/ui/home/HomeViewModel.kt)): el usuario ve **sus** filas (cualquier `state`, incl. planned propios) **o** entrenos de gente a la que sigue con `state != planned` (no se listan *planned* de terceros).
- **Borrador**: no hay un tercer `workout_state` “draft” en el flujo de guardado Android; en Add, “draft” en código suele referirse a **filas de ejercicio** en el editor de fuerza, no a un entreno fantasma en BD. Un borrador de producto al estilo iOS requeriría acuerdo de esquema/RLS.

## Cuenta atrás antes del activo

| Entrada | Comportamiento |
|--------|----------------|
| **Start** en [WorkoutDetailScreen](app/src/main/java/com/lilru/liftr/ui/home/WorkoutDetailScreen.kt) (fuerza, cardio o sport) | [StartWorkoutCountdownScreen](app/src/main/java/com/lilru/liftr/ui/home/StartWorkoutCountdownScreen.kt) salvo `LiftrPreferences.skipStartCountdown` → luego [Active*WorkoutScreen](app/src/main/java/com/lilru/liftr/ui/active/) correspondiente. |
| **Planned** con participantes: diálogo *dual* (con pareja o solo) al preparar fuerza vinculada | Misma política de countdown que el botón Start (helper `openStrengthActiveWithCountdownPolicy` + mismo pref). |
| **Detalle desde** Home, Search, Ranking, competición, notificación/overlay (tras resolver owner en [WorkoutDetailFromNotificationOverlay](app/src/main/java/com/lilru/liftr/ui/home/WorkoutDetailFromNotificationOverlay.kt) si hace falta) | Todos componen el mismo `WorkoutDetailScreen` → **no** hay atajo a activo sin pulsar *Start* (misma UX que iOS al abrir un planned). |
| Reanudar app / notificación persistente (FGS) mientras un activo sigue en primer plano | Sigue en la `Active*Screen` ya montada; **nueva** apertura del entreno pasa otra vez por el detalle si se cerró. |

- **Skip**: [LiftrPreferences](app/src/main/java/com/lilru/liftr/prefs/LiftrPreferences.kt) `skipStartCountdown` — ajuste en [ProfileTabScreen](app/src/main/java/com/lilru/liftr/ui/profile/ProfileTabScreen.kt) (perfil propio) además de lectura en código.
- **Add tab**: crea el entreno y, si enseña el detalle, aplica la tabla anterior; no hay otra ruta a activo en el código.

## Core

- [x] Modos **Add** / **Plan** y criterio **planned** en feed único (más nota “borrador” arriba).
- [x] Fuerza: editor por persona, plantillas, rutinas y carpetas (`strength_routine_*`) — UI en [AddStrengthRoutinesSheetContent](app/src/main/java/com/lilru/liftr/ui/add/AddStrengthRoutinesSheetContent.kt). Paridad de flujo con [AddWorkoutSheet.swift](../../Liftr/AddWorkoutSheet.swift) revisada (carpetas, reemplazar rutina, orden, aplicar al editor); regresión manual al cambiar lógica en [AddWorkoutViewModel](app/src/main/java/com/lilru/liftr/ui/add/AddWorkoutViewModel.kt).
- [x] Drop sets de fuerza: Add, editar detalle, duplicar y activo conservan `weight_segments` con 2+ pasos `{ reps, weight_kg }`. En Android revisar [StrengthExerciseDraftsEditorBlock](app/src/main/java/com/lilru/liftr/ui/add/StrengthExerciseDraftsEditorBlock.kt), [EditStrengthWorkoutMetaSheetContent](app/src/main/java/com/lilru/liftr/ui/home/EditStrengthWorkoutMetaSheetContent.kt), [DuplicateWorkoutFromDetailLoader](app/src/main/java/com/lilru/liftr/ui/add/duplicate/DuplicateWorkoutFromDetailLoader.kt) y [ActiveStrengthWorkoutViewModel](app/src/main/java/com/lilru/liftr/ui/active/ActiveStrengthWorkoutViewModel.kt); en iOS revisar `StrengthSetRowEditor`, `EditWorkoutMetaSheet`, `WorkoutDetailView` y `ActiveStrengthWorkoutView`.
- [x] Rutinas de fuerza: la tarjeta abre previsualización antes de aplicar, la edición usa hoja dedicada y el overwrite muestra diferencias de prescripción antes de actualizar la plantilla guardada. El fingerprint compara ejercicios, series, notas, descanso, RPE y `weight_segments`; no debe actualizar rutinas si la prescripción incompleta no puede serializarse.
- [x] Cardio: **ruta GPS** en `OngoingWorkoutService` (FGS location) + `route_geojson` al finalizar; **competición** — [CompetitionSubmit](app/src/main/java/com/lilru/liftr/competition/CompetitionSubmit.kt) `submitWorkoutToCompetitionIfActive` **solo** tras crear en Add (como iOS). Al **publicar** un `planned` desde [WorkoutDetailViewModel](app/src/main/java/com/lilru/liftr/ui/home/WorkoutDetailViewModel.kt) solo se actualiza `workouts` (misma paridad que `publishWorkout` en Swift, sin `submit_workout_to_competition`).

### Publicar `planned` y competición (resumen)

| Plataforma | Tras tocar *Publish* en detalle (planned) |
|------------|-----------------------------------------|
| **iOS** | Sólo actualiza fila `workouts` (p. ej. a `published`). **No** submit a competición desde esta acción. |
| **Android** | Sólo actualiza `workouts` (misma implementación paridad; sin submit a competición al publicar). |
- [x] Sport / Hyrox: `create_sport_workout_v2` con `p` + `p_stats` (wrapper JSON como iOS). Hyrox: `p_stats.exercises` se normaliza con [HyroxExerciseFormatting.persistedPayload](app/src/main/java/com/lilru/liftr/hyrox/HyroxExerciseFormatting.kt) (misma regla que iOS) antes del RPC; tras insert, patch opcional de `exercise_display_name` en `hyrox_session_exercises` ([patchHyroxExerciseDisplayNamesIfNeeded](app/src/main/java/com/lilru/liftr/ui/add/AddWorkoutViewModel.kt)). Éxito Add/Plan: mismos textos que iOS (`add_strength_success_published` / `planned`, genéricos “Workout published/planned”).
- [x] Participantes y *linked strength* en Add: al guardar, *same session* → `create_strength_workout` + `add_workout_participant` por followee; *per person* → `plan_strength_squad_programs` (un workout por persona). `create_linked_strength_workout_copy` no se llama al guardar (igual que iOS); vinculación al **Start** desde el detalle — copy en [strings](app/src/main/res/values/strings.xml) `add_group_same_session_linked_hint` y ayuda [WorkoutHelpScreen](app/src/main/java/com/lilru/liftr/ui/add/WorkoutHelpScreen.kt) “Linked workouts”.
- [x] Duplicar desde detalle: revisar alineación con almacenamiento iOS.
- [x] Recomendaciones (`WorkoutRecommendation*`) en árbol Android; copy/UX y textos alineados con [WorkoutRecommendationFlowView](Liftr/WorkoutRecommendationFlowView.swift) (fase “Building suggestion…”, intros Hyrox, errores “Couldn’t load”).

- [x] Metadatos en detalle (`EditWorkoutMeta*`, paridad con iOS `EditWorkoutMetaSheet`): **cardio** — `workouts` + `cardio_sessions` + `cardio_session_stats` ([updateCardioWorkoutMeta](app/src/main/java/com/lilru/liftr/ui/home/WorkoutDetailViewModel.kt), [EditCardioWorkoutMetaSheetContent](app/src/main/java/com/lilru/liftr/ui/home/EditCardioWorkoutMetaSheetContent.kt)); **sport** — `update_sport_workout_v2` con `p_stats` de [SportStatsPayloadBuilder](app/src/main/java/com/lilru/liftr/ui/add/SportStatsPayloadBuilder.kt) + carga [loadSportEditEnrichment](app/src/main/java/com/lilru/liftr/ui/add/duplicate/DuplicateWorkoutFromDetailLoader.kt) (Hyrox: patch nombres tras RPC); **sport sin fila de sesión** o sólo título/notas: `workouts` vía [updateWorkoutMetaCommon](app/src/main/java/com/lilru/liftr/ui/home/WorkoutDetailViewModel.kt) (también `strength`/`cardio` sin sesión). **Fuerza** — hoja con metadatos + `workout_exercises` + `exercise_sets`: [EditStrengthWorkoutMetaSheetContent](app/src/main/java/com/lilru/liftr/ui/home/EditStrengthWorkoutMetaSheetContent.kt) + [saveStrengthWorkoutWithExercises](app/src/main/java/com/lilru/liftr/ui/home/WorkoutDetailViewModel.kt) (carga: [loadStrengthEditsForWorkout](app/src/main/java/com/lilru/liftr/ui/home/DetailStrengthEditLoader.kt)).

## Comentarios (detalle de entreno)

- [x] Hilo: comentarios raíz y respuestas orden por `created_at` ASC, likes y borrado lógico en [WorkoutDetailViewModel](app/src/main/java/com/lilru/liftr/ui/home/WorkoutDetailViewModel.kt) + UI [WorkoutDetailScreen](app/src/main/java/com/lilru/liftr/ui/home/WorkoutDetailScreen.kt) (revisar frente a `CommentView` en iOS si el producto añade orden alternativo o paginación).

## Plataforma

- [x] Android: `HealthConnectImportScreen` + `importHealthConnectSessionToCardio` (RPC `CREATE_CARDIO_WORKOUT_V2`) y diálogo de confirmación.
- [x] Banners: `BuildConfig.AD_BANNER_UNIT_ID` desde `admob.bannerId` en [local.properties](local.properties.example) (test de Google por defecto).
- [x] Cuenta atrás previa a activo — ver sección arriba; ajuste global con `LiftrPreferences`.

Marca filas al validar con backend y pruebas manuales.
