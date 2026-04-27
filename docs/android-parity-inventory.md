# Inventario de paridad iOS → Android (Liftr)

Mapea los módulos y pantallas del cliente Swift a equivalentes en Android. Úsalo para priorizar el **MVP de Play** y fases sucesivas.

## Estado reciente (abril 2026)

Resumen: el cliente Android en `android/` cubre las mismas áreas principales que iOS (tabs Home / Search / Add / Ranking / Profile, competición, metas, logros, comparar, recomendaciones, notificaciones + FCM, billing Premium, Health Connect import, calendario de actividad en perfil, datos personales y borrar cuenta, GPS cardio + `route_geojson`, FGS + widget de entreno activo). Detalle Add Workout: [`android/ADD_WORKOUT_PARITY.md`](../android/ADD_WORKOUT_PARITY.md). Notificación con `competition_id` abre detalle en ambas plataformas (Android `CompetitionDetailFromIdScreen`; iOS `CompetitionDetailFromIdView` en `CompetitionDetailView.swift`).

**Nota:** Las tablas inferiores son históricas; muchas filas marcadas **F2** ya tienen pantalla en Android — usar el código y este párrafo como fuente de verdad.

## Leyenda

- **MVP** — Objetivo primera versión en Google Play.
- **F2** — Segunda ola.
- **Plataforma** — Sustitución iOS (HealthKit, ActivityKit) por API Android o servicio de terceros.
- **Backend** — Ya cubierto vía [Supabase](../Liftr/SupabaseManager.swift) en ambos clientes (RLS, auth, etc.).

## Mapas, anuncios y notificaciones

| Tema | iOS | Android / notas | Prioridad |
|------|-----|------------------|-----------|
| **Mapas / cardio con ruta** | `CardioWorkoutLocationTracker` | [Play services Location](https://developer.android.com/develop/sensors-and-location) + permisos según [política de Play](https://support.google.com/googleplay/android-developer) | MVP si la v1 ofrece cardio con ruta; si no, F2 |
| **Anuncios** | `BannerAdView`, `TopBanner`, etc. | Misma red; SDK Android; declarar en consola | MVP si hay paridad con anuncios en iOS; si no, F2 |
| **Push** | `NotificationTokenUploader`, APNs | [FCM](https://firebase.google.com/docs/cloud-messaging); subir el token con el flujo hacia Supabase/edge (como en iOS) | MVP al priorizar notificaciones |

## Autenticación y perfil

| iOS (Swift) | Notas | Prioridad |
|-------------|--------|-----------|
| `LoginView`, `RegisterView` | Email/contraseña o flujos que exponga Supabase Auth | MVP |
| `ProfileView`, `EditBioSheet`, `AvatarMini` | Perfil de usuario | MVP |
| `ProfileGate` | Lógica de acceso; replicar en Android (nav condicional) | MVP |
| `SearchView` | [`SearchTabScreen`](../android/app/src/main/java/com/lilru/liftr/ui/search/SearchTabScreen.kt) | MVP (hecho) |
| `FollowersListView` | [`FollowersListScreen`](../android/app/src/main/java/com/lilru/liftr/ui/profile/FollowersListScreen.kt) | MVP (hecho) |
| `ContactSupportForm` | [`ContactSupportScreen`](../android/app/src/main/java/com/lilru/liftr/ui/profile/ContactSupportScreen.kt) | MVP (hecho) |

## Entrenamientos (core)

| iOS | Notas | Prioridad |
|-----|--------|-----------|
| `HomeView`, `RootView`, `AppState` | Shell de la app, estado global | MVP |
| `AddWorkoutSheet` | Crear / plantillas | MVP |
| `WorkoutCard`, `WorkoutDetailView` | Lista y detalle | MVP |
| `ActiveStrengthWorkoutView`, `ActiveCardioWorkoutView`, `ActiveSportWorkoutView` | En vivo, temporizador, series | MVP |
| `StartWorkoutCountdownView` | [StartWorkoutCountdownScreen](android/app/src/main/java/com/lilru/liftr/ui/home/StartWorkoutCountdownScreen.kt) — sólo vía [WorkoutDetailScreen](android/app/src/main/java/com/lilru/liftr/ui/home/WorkoutDetailScreen.kt); mapa de entradas en sección *Cuenta atrás* de [`ADD_WORKOUT_PARITY`](../android/ADD_WORKOUT_PARITY.md) | MVP (hecho) |
| `EditWorkoutMetaSheet` | Metadatos (nombre, fecha, etc.) | MVP |
| `WorkoutHelpSheet` | Ayuda in-app | F2 |
| `WorkoutLiveActivityManager`, `LiftrWorkoutActivityKit`, widgets Live Activity | [ActivityKit] → en Android: notificación persistente, FGS, widget, según paridad deseada | Plataforma / F2 |
| `WorkoutRecommendationFlowView`, `WorkoutRecommendationService` | `WorkoutRecommendation*` en Android | MVP (hecho) |
| `CardioWorkoutLocationTracker` | Permisos ubicación, tracking | MVP si cardio con mapa; si no, F2 |
| `CardioKmPaceSplits` | Splits; datos desde modelo | MVP/F2 |
| Varios: `Decoders`, `Helpers`, set rows, pickers | Infra reutilizable en capas de datos y UI | MVP (incremental) |

## Salud y dispositivos

| iOS | Android equivalente | Prioridad |
|-----|--------------------|-----------|
| `HealthKitCardioImportService`, `AppleHealthImportView`, `AppleHealthImportHelpSheet` | [`HealthConnectImportScreen`](../android/app/src/main/java/com/lilru/liftr/ui/health/HealthConnectImportScreen.kt) (mismo RPC cardio v2) | Plataforma distinta; paridad de producto |
| Integración Apple Watch / extensiones (si aplica) | Wear OS / otras — Roadmap | Plataforma |

## Competición

| iOS (carpeta `Competition/`) | Prioridad |
|------------------------------|-----------|
| `CompetitionsHubView`, `CompetitionDetailView`, `CreateCompetitionView` | `ui/competition/*` en Android | MVP (hecho) |
| `CompetitionService`, reviews, etc. | Mismas tablas Supabase | MVP (hecho) |

## Social y recompensas

| iOS | Prioridad |
|-----|-----------|
| `CommentView` | Comentarios en `WorkoutDetailScreen` / ViewModel | MVP (hecho) |
| `RankingView`, `UserLevelDetailView` | `RankingTabScreen`, `UserLevelDetailScreen` | MVP (hecho) |
| `AchievementsGridView`, `AchievementsFromNotificationView` | `AchievementsScreen` | MVP (hecho) |
| `NotificationsListView`, `NotificationTokenUploader` | FCM + `NotificationsScreen` | MVP (hecho) |
| `GoalsView`, `GoalsManager`, `GoalsModels`, `GoalContributionsView` | `GoalsScreen`, `GoalContributionsScreen` | MVP (hecho) |

## Consistencia y análisis

| iOS | Prioridad |
|-----|-----------|
| `ConsistencyDrillDownView`, `ConsistencyChartMetric` | `ConsistencyDrillDownScreen`, `ProfileProgressScreen` | MVP (hecho) |
| `CompareWorkoutsView`, `ComparePRsView` | `CompareWorkoutsScreen`, `ComparePrsScreen` | MVP (hecho) |
| `HyroxExerciseFormatting` | `hyrox/HyroxExerciseFormatting.kt` | MVP (hecho) |

## Monetización y anuncios

| iOS | Notas | Prioridad |
|-----|--------|-----------|
| `BannerAdView`, `TopBanner` (si ads) | SDK de la red (p. ej. **Google Mobile Ads**) en su variante Android | Alinear a política Play; MVP solo si iOS lo tiene en el mismo tramo de release |

## Otros

| iOS | Prioridad |
|-----|-----------|
| `FeatureRequests*`, `FAQsView` | `FeatureRequests*`, `FaqsScreen` | MVP (hecho) |
| `RegisterView` / términos (si distintos por tienda) | Legal / MVP |

## Resumen MVP sugerido (mínimo razonable para pista cerrada en Play)

1. Auth (Supabase) y sesión.
2. Shell principal: home, lista/detalle de entrenamientos, inicio/edición de un flujo básico de **fuerza o cardio** (elegid uno y extender).
3. Sincronización con las mismas tablas/API que iOS; pruebas contra RLS.
4. Notificaciones push (FCM) y subida de token, si iOS lo exige hoy.
5. Health Connect y competición ya están en el cliente Android; validar con builds release (R8) y pruebas manuales antes de Play.

Este inventario se actualiza añadiendo o quitando filas al evolucionar el repositorio Swift.
