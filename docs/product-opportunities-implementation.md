# Oportunidades de producto — decisiones y especificación

Documento de seguimiento al inventario de repo y roadmap de oportunidades. **No sustituye** el plan adjunto en Cursor; concreta los entregables operativos para el equipo (north star, paridad Android, rutas/GPX/privacidad, calendario, clubes).

---

## Resumen para producto (lectura rápida)

### Qué tenéis hoy

- **Entrenos:** fuerza (series, rutinas con carpetas, PRs), cardio con GPS y ruta, muchos deportes con stats, **Hyrox**, entreno **en grupo en el mismo móvil** (dual/trio).
- **Día a día:** feed, seguir, likes y comentarios, búsqueda de usuarios y entrenos.
- **Motivación:** metas semanales, consistencia, logros, XP/niveles, ranking, duels, competiciones.
- **Análisis:** comparar entrenos (incl. periodos y otro usuario).
- **Datos:** import Apple Health / Health Connect, recomendaciones.
- **Producto:** notificaciones, premium (p. ej. Android), anuncios donde aplique, entreno en curso (Live Activity, widget, FGS).

En conjunto: **registro + social + competición + gamificación + salud**. Lo que suele faltar son otro tipo de frentes: rutas reutilizables, grupos permanentes, planificación muy visible, reloj, integraciones externas.

### Qué podéis añadir (por bloque)

| Bloque | Ejemplos |
|--------|----------|
| **Planificación** | Pantalla “Plan” que una calendario + metas de la semana + acceso a rutinas; más adelante recordatorios de lo planeado. |
| **Rutas / cardio** | Rutas guardadas, privacidad de mapa (recorte inicio/fin en lo público), export GPX. |
| **Comunidad estable** | Clubes/grupos con miembros y retos ligeros (sin chat al inicio). |
| **Profundidad entrenador** | RPE/RIR, deload visible, modo coach (más coste en roles/permisos). |
| **Plataforma** | Apple Watch con flujo cardio, integraciones tipo Strava/Garmin. |
| **Crecimiento / confianza** | Onboarding por objetivo, reportes, web mínima con enlaces. |

### Cómo elegir por dónde empezar

- Si el crecimiento viene del **outdoor y el mapa** → priorizar rutas guardadas, privacidad, GPX.
- Si viene del **gym, Hyrox y la rutina** → priorizar calendario/plan y profundidad de series.
- Si viene de **clubs o equipos** → priorizar grupos persistentes.

| Si priorizáis… | Primer bloque de implementación razonable |
|----------------|---------------------------------------------|
| Planificación | Calendario / Plan fase 0 → luego planificación explícita ampliada |
| Cardio / mapa | Rutas guardadas + privacidad → export GPX |
| Comunidad | Grupos MVP → retos dentro del grupo |
| Reloj | Watch acotado para cardio |

### Orden de trabajo en la app (lista numerada)

1. **North star** — Confirmar o **aceptar por defecto** el §1.1–1.2 (no exige código en la app).
2. **Proceso iOS/Android** — Aplicar la regla de paridad del §1.3 en cada PR con cambio de contrato.
3. **Calendario / Plan (fase 0)** — Primera pieza grande de producto nueva recomendada: §3.
4. **Rutas + privacidad + GPX** — §2.
5. **Clubes (MVP)** — §4.
6. **Resto** — Watch, integraciones externas, segmentos globales, etc., según prioridad de negocio.

---

## 1. North star y política de paridad Android

### 1.1 Posicionamiento recomendado (decisión de trabajo)

**North star por defecto:** *herramienta de registro y análisis multi-modal (fuerza, cardio, deporte, Hyrox) con comunidad y gamificación*, no una red outdoor tipo Strava como eje único.

| Eje | Rol en Liftr |
|-----|----------------|
| **Herramienta** | Core: entrenos, rutinas, comparativas, metas, salud/import, entreno activo. |
| **Comunidad** | Feed, follows, likes, comentarios, competiciones, ranking, duels, búsqueda. |
| **Diferenciador** | Hyrox, fuerza en grupo (dual/trio), motor de recomendaciones, comparar periodos. |

Si en 12–24 meses el crecimiento dependiera **más** del descubrimiento outdoor público, se desplazaría el peso hacia rutas compartidas y segmentos; si dependiera **más** del gym/programación, hacia calendario, RPE y posible modo coach. La fila superior del changelog y [`backend-contracts.md`](backend-contracts.md) reflejan el mix actual (más herramienta + social que mapa global).

### 1.2 Usuario referencia (para priorizar backlog)

**Persona por defecto:** atleta que mezcla **fuerza + cardio condicionado** y puede orientarse a **Hyrox** o deporte de equipo; no solo “corredor casual con mapa”. Las features tipo Strava (segmentos, heatmap) se evalúan como **ampliación**, no como bloqueador del mensaje principal.

### 1.3 Regla de paridad iOS / Android

**Contrato:** iOS sigue siendo fuente de verdad de **nombres de tablas/RPC** hasta que se documente lo contrario ([`docs/backend-contracts.md`](backend-contracts.md)); Android debe usar [`android/.../BackendContracts.kt`](../android/app/src/main/java/com/lilru/liftr/data/BackendContracts.kt) sin strings sueltos en queries nuevas.

**Releases:**

| Tipo de cambio | Política sugerida |
|----------------|-------------------|
| **Cambio de contrato** (tabla/RPC nueva o firma distinta) | Mismo sprint: actualizar `backend-contracts.md`, `BackendContracts.kt`, y **ambos** clientes **o** ventana explícita “iOS first” con **máx. 1 release** de desfase y ticket Android enlazado. |
| **Solo UI / plataforma** (Live Activity, FGS, HealthKit vs Health Connect) | Paridad de **producto** (misma capacidad), implementación nativa independiente; seguir [`android-parity-inventory.md`](android-parity-inventory.md). |
| **Bugfix solo en un cliente** | Permitido; documentar en changelog por plataforma. |

**Resumen:** *paridad de producto sí; mismo día de código no siempre*, salvo cambios de API compartida, donde el desfase debe ser consciente y corto.

---

## 2. Rutas guardadas, privacidad de mapa y GPX (antes de segmentos globales)

### 2.1 Por qué esta secuencia

- **Segmentos de comunidad** implican geoespacial en servidor, moderación, leaderboards por tramo y coste operativo; encajan mejor **después** de dominar rutas personales y export.
- **Rutas guardadas + privacidad + GPX** encajan con el stack actual: ya persistís **`route_geojson`** en flujos cardio ([`ActiveCardioWorkoutViewModel.kt`](../android/app/src/main/java/com/lilru/liftr/ui/active/ActiveCardioWorkoutViewModel.kt), detalle con parser en [`CardioRouteGeoJson.kt`](../android/app/src/main/java/com/lilru/liftr/cardio/CardioRouteGeoJson.kt) / iOS equivalente).

### 2.2 Rutas guardadas (MVP)

**Objetivo:** reutilizar una polilínea conocida al iniciar cardio (“correr la misma ruta”) sin redescubrimiento tipo Strava.

**Modelo mínimo (propuesta):**

- Tabla `saved_routes` (o nombre alineado a convención actual): `id`, `user_id`, `name`, `route_geojson` (text/JSON), `distance_m` opcional, `created_at`, `source_workout_id` nullable (referencia al entreno del que se extrajo).
- RLS: solo el dueño lee/escribe.
- Cliente: en detalle de cardio o al finalizar, acción “Guardar ruta”; en Add/Active cardio, picker “Rutas guardadas” que precarga mapa/meta pero **no** sustituye permisos GPS en vivo.

**Alternativa más ligera (sin tabla):** duplicar entreno anterior y limpiar stats; peor UX de biblioteca y deduplicación.

### 2.3 Zonas de privacidad

**Objetivo:** ocultar inicio/fin cerca de casa en **vistas públicas** (feed, perfil de otro usuario, competición).

**Opciones:**

| Enfoque | Pros | Contras |
|---------|------|---------|
| **Recorte de polilínea** al publicar/compartir (metros iniciales/finales) | Simple; un solo GeoJSON “público” | Pierde distancia exacta en mapa público |
| **Dos campos** `route_geojson` (completo, solo dueño) y `route_geojson_public` (recortado) | Claridad legal/UX | Migración y doble mantenimiento |
| **Offset aleatorio** fijo por usuario | Menos precisión para stalking | Menos fiel al trazo real |

**Recomendación:** empezar por **recorte configurable** (p. ej. 200–500 m) en ajustes de perfil + aplicación al generar payload público; el dueño sigue viendo ruta completa en su detalle.

### 2.4 Export GPX

**Objetivo:** reducir lock-in y atraer usuarios de Garmin/Coros; complementa import vía Health.

**MVP:** generar GPX `<trk>` / `<trkseg>` / `<trkpt lat lon>` a partir de coordenadas ya parseadas de `route_geojson` (mismo origen que [`CardioRouteGeoJson.parseLineStringLatLng`](../android/app/src/main/java/com/lilru/liftr/cardio/CardioRouteGeoJson.kt)). Compartir vía sheet de sistema (iOS/Android). Opcional: elevación si existe en stats.

**Import GPX** puede ser F2 si Health cubre la mayoría de usuarios iOS; valorar duplicados contra UUID/hash.

### 2.5 Segmentos (MVP técnico y alcance)

**Decisión de alcance (MVP v1):** solo **segmentos creados explícitamente por el usuario** (p. ej. desde un cardio publicado con `route_geojson` o, más adelante, dibujo en mapa). **Queda fuera del MVP** la generación “automática” de candidatos por clustering de muchas rutas y su curación masiva (equivalente a sugerencias estilo Strava sin paso humano claro).

**Criterio de entrada de producto** (sin cambiar el orden del §2.1): segmentos de comunidad siguen encajando **después** de dominar rutas guardadas, privacidad de mapa y export GPX cuando el volumen y moderación lo justifiquen.

**Implementación en repo:** migración `docs/migrations/segments_mvp_v1.sql` (PostGIS, tablas `segments` / `segment_efforts`, RLS, RPCs y disparador de matching al publicar cardio). Si el cliente SQL parte el script por `;` (p. ej. DBVisualizer “execute statement”), usar en orden `docs/migrations/segments_mvp_v1_part01_schema.sql` … `segments_mvp_v1_part06_read_functions_and_grants.sql`, **cada archivo entero en una sola ejecución**. Contratos en [`docs/backend-contracts.md`](backend-contracts.md) y [`BackendContracts.kt`](../android/app/src/main/java/com/lilru/liftr/data/BackendContracts.kt).

**Privacidad y §2.3:** la geometría pública de un segmento es una **polilínea de catálogo** (eje + buffer en servidor). Debe **respetar la misma política** que acabará aplicando el recorte de mapa público: al crear un segmento desde un entreno, el usuario asume que el tramo elegido puede mostrarse en leaderboards y mapas públicos; cuando exista `route_geojson_public` o recorte configurable, el flujo de creación deberá **partir de la geometría ya recortada** o advertir explícitamente (evitar filtrar domicilio vía segmentos antes de tener recorte en publicación).

---

## 3. Vista calendario unificada (diseño sobre datos existentes)

### 3.1 Estado actual

- **Perfil:** calendario mensual con intensidad por día y lista de entrenos del día seleccionado (iOS `ProfileView` / `loadMonthActivity`; Android [`ProfileCalendarCard.kt`](../android/app/src/main/java/com/lilru/liftr/ui/profile/ProfileCalendarCard.kt) + [`ProfileMonthCalendarViewModel.kt`](../android/app/src/main/java/com/lilru/liftr/ui/profile/ProfileMonthCalendarViewModel.kt)).
- **Entrenos planeados:** en ambas plataformas el calendario ya distingue filas con `state == "planned"` (celdas con estilo “planned”). La **fase 0** de Plan puede reutilizar esa misma carga; ampliar flujos “crear/editar plan” es trabajo de producto adicional (fase 1).
- **Home:** feed agrupado por día, metas semanales como módulo separado.
- **No hay** una sola pantalla dedicada **Plan** que una vista mensual/semanal del usuario actual + **resumen de meta semanal** + atajos a rutinas en un solo sitio (la pieza que falta es sobre todo **navegación y composición de UI**, no necesariamente nuevo contrato en fase 0).

### 3.2 Visión de producto

Una pantalla **Plan / Calendario** (nombre de marketing abierto) que responda: *¿qué hice y qué me queda esta semana/mes?*

### 3.3 Fuentes de datos (sin tablas nuevas en fase 0)

| Fuente | Qué aporta | Cómo mostrarlo |
|--------|------------|----------------|
| `workouts` (+ tipos) | Hecho + borradores si existen en modelo | Celdas por `started_at` / fecha efectiva |
| `weekly_goals` + `weekly_goal_results` | Objetivo semanal agregado | Barra o badge en semana ISO actual |
| `strength_routines` (+ carpetas) | Plantillas | Acceso rápido “Aplicar rutina hoy” desde calendario (abre Add con prefill) |

### 3.4 Fases

| Fase | Alcance |
|------|---------|
| **0** | Entrada de navegación nueva (“Plan” / “Calendario”) que reutiliza la misma lógica de agregación mensual que el perfil para el **usuario actual**, más resumen de **metas semanales** (reutilizar datos ya cargados en Home/Goals si es posible), chips o filtro por tipo de entreno en la lista del día, y atajo a **rutinas** (abrir flujo Add con plantilla). Sin tablas nuevas si no es imprescindible. |
| **1** | Completar el ciclo de **planeado**: ya existe `workouts.state == "planned"` en calendario; falta pulir creación/edición/publicación, vistas agregadas y **notificaciones** opcionales; valorar RPC/listados dedicados sin cargar todo el histórico. |
| **2** | Mesociclos / deload: plantillas de semana o integración con recomendador existente. |

### 3.5 Consideraciones técnicas

- Reutilizar zonas horarias ya usadas en feed (`ZoneId` Android / `Calendar` iOS).
- Si se añade planificación persistente, actualizar [`backend-contracts.md`](backend-contracts.md) y RPCs de listado para no cargar todo el histórico en el cliente.

---

## 4. Club / grupo persistente vs ampliar competiciones

### 4.1 Qué cubren hoy las competiciones

Tablas y flujo ya inventariados: `competitions`, `competition_blocks`, `competition_goals`, `competition_workouts`, reviews, estados `finished`, leaderboards de duels ([`docs/backend-contracts.md`](backend-contracts.md), migraciones de ranking/duels). El modelo es **evento acotado** (fechas, envíos, ganador), no comunidad permanente.

### 4.2 Hueco de producto

**Club Strava-like:** identidad estable, miembros, actividad recurrente, retos ligeros **sin** ciclo de revisión de competición formal.

### 4.3 Opciones

| Opción | Descripción | Pros | Contras |
|--------|-------------|------|---------|
| **A. Extender `competitions`** | `type = recurring` / `club_id`, competiciones hijas semanales | Menos tablas nuevas | Mezcla mental “liga” vs “grupo”; RLS y UI más complejos |
| **B. Nuevo módulo `groups` (recomendado MVP)** | `groups`, `group_members` (role), opcional `group_posts` o filtro de feed `group_id` | Separación clara | Más migración inicial |

### 4.4 MVP recomendado (opción B)

1. **`groups`:** `id`, `name`, `slug` opcional, `owner_user_id`, `description`, `is_private`, `created_at`.
2. **`group_members`:** `group_id`, `user_id`, `role` (`owner` | `admin` | `member`), `joined_at`; invitación por link o búsqueda de usuarios (F2).
3. **Feed:** Fase 1 — filtro “Solo este club” que limite workouts a `user_id IN (miembros)` **o** etiqueta `group_id` en workouts (migración) si queréis solo entrenos explícitos del club.
4. **Retos:** Fase 1 — reutilizar `weekly_goals` con metadata `group_id` opcional **o** tabla mínima `group_challenges` (meta + fechas + `group_id`).
5. **Chat:** explícitamente fuera del MVP (coste moderación); usar notificaciones push para anuncios de admin si hiciera falta.

### 4.5 Relación con competiciones actuales

Un club puede **lanzar** una competición existente (FK opcional `competitions.sponsor_group_id` en el futuro). Para MVP, bastan deep links y copy en UI sin acoplar esquemas.

---

## 5. Checklist para empezar implementación

### Punto 1 del orden de trabajo (north star)

- **No requiere código** si el equipo **acepta** el posicionamiento por defecto del §1.1–1.2.
- Si queréis reflejarlo en app más adelante: onboarding por objetivo o etiquetas de perfil son **F2**; no bloquean el resto.

### Punto 3 — Calendario / Plan fase 0 (primer desarrollo grande recomendado)

Datos de producto que conviene fijar **antes** o al abrir el PR:

| Decisión | Por qué importa |
|----------|-----------------|
| **Punto de entrada** | ¿Nueva pestaña en el tab principal, ítem en Home, o acceso desde Perfil? Afecta navegación (`RootView` / `MainActivity` / nav hosts) y carga inicial. |
| **Nombre visible** | Copy para título, strings iOS/Android, posible icono. |
| **Alcance de usuario** | ¿Solo “yo” o también vista de plan para otro perfil? (El calendario de perfil ajeno ya existe; Plan suele ser **solo propio**.) |
| **Metas semanales en la misma pantalla** | ¿Resumen compacto (barra/progreso) vs botón que abre `Goals`? Define si reutilizáis ViewModels existentes o duplicáis una query mínima. |
| **Atajo a rutinas** | ¿Sheet/lista de `strength_routines` o deep link al flujo Add existente con `routine_id`? Hay que alinear con el flujo actual de “empezar desde rutina”. |

**Datos técnicos ya disponibles en repo:** conteos por día y lista diaria vía `workouts` (+ participantes); estado `planned` en grid; patrones en `ProfileView.swift` y `ProfileMonthCalendarViewModel.kt`. Reutilizarlos reduce riesgo.

---

## 6. Referencias cruzadas

| Documento | Uso |
|-----------|-----|
| [`backend-contracts.md`](backend-contracts.md) | Tablas/RPC; actualizar al añadir rutas, planificación o grupos |
| [`android-parity-inventory.md`](android-parity-inventory.md) | Mapa pantalla a pantalla |
| [`android-strategy.md`](android-strategy.md) | Decisión de stack Android |
| [`publishing.md`](publishing.md) | Tiendas y releases |
| [`Liftr/changelog.md`](../Liftr/changelog.md) | Historial de producto |

---

*Última actualización: abril 2026 — añadido resumen de producto, orden numerado de trabajo y checklist de implementación (incl. `planned` en calendario).*
