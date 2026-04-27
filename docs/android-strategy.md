# Estrategia de cliente Android (Liftr en Google Play)

Fecha de decisión: documento vivo; revisar al cambiar de stack.

## Decisión

| Ámbito | Elección | Motivo |
|--------|----------|--------|
| Plataforma | **Android nativo (Kotlin + Jetpack Compose)** | Paridad con [publishing.md](publishing.md) §3 (nativo Android) para Play con riesgo controlado; dos bases (Swift + Kotlin) y UIs alineadas con guías de cada plataforma. |
| Ubicación del código | **Monorepo** (`android/` en este repositorio) | Mismas migraciones [Supabase](../supabase/…), un solo sitio para issues de producto y alinear contratos API. Si más adelante se prefiere un repositorio hermano, el módulo se puede extraer con `git subtree` o copiando el árbol. |
| Lógica compartida (futuro) | Opcional **Kotlin Multiplatform (KMP)** en una fase posterior | No es requisito para el MVP. Si el dominio crece, valorar módulo `shared` con KMP sin bloquear el arranque en Android nativo. |
| Rechazado por ahora | Flutter / React Native como reescritura unificada | Implica migración o duplicación fuerte a medio plazo; se descarta salvo cambio de prioridad de negocio. |

## Criterios de repesca

- Si en el futuro se exige **un solo código móvil**, reevaluar Flutter o RN (coste: migrar el cliente iOS hacia ese stack).
- Si se prioriza **lógica idéntica** y dos UIs, replantear **KMP** (Compose + SwiftUI).

## Referencias

- Paridad de funcionalidad: [android-parity-inventory.md](android-parity-inventory.md)
- Código: [../android/README.md](../android/README.md)
- Publicación: [android-play-release.md](android-play-release.md) y [publishing.md](publishing.md)
