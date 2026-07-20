# Pruebas de regresión UI de iOS

El workflow [`.github/workflows/ios-regression-tests.yml`](../.github/workflows/ios-regression-tests.yml) valida los recorridos críticos de iOS contra una rama efímera de Supabase. No genera archivos para TestFlight: complementa el build de Xcode Cloud y el workflow de Android con pruebas de comportamiento y datos aislados.

## Cuándo se ejecuta

- En cada `push` a `main`.
- En tags `v*`.
- Manualmente desde **GitHub Actions → iOS regression tests → Run workflow**.
- Solo se mantiene una ejecución activa por workflow y referencia; una nueva ejecución cancela la anterior.

El flujo normal es `devel` → [sincronización automática de `main`](../.github/workflows/main.yml) → regresión UI en `main`. Los cambios Android se validan por separado en [`.github/workflows/android.yml`](../.github/workflows/android.yml).

## Arquitectura del flujo

1. Instala Supabase CLI y los clientes `psql`/`pg_dump`.
2. Crea `ui-regression-<run_id>` mediante [`supabase-branch-create.sh`](../scripts/ci/supabase-branch-create.sh), usando `Liftr/` como workdir canónico de Supabase.
3. Si las migraciones no pueden reconstruir el baseline, copia los esquemas `public`, `auth` y `extensions` del proyecto padre a la rama.
4. Ejecuta [`ui_regression_user.sql`](../Liftr/supabase/seed/ui_regression_user.sql) y comprueba login, RPCs de mascotas y fixtures.
5. Selecciona un simulador iPhone disponible y ejecuta las 14 clases permitidas explícitamente en el workflow, sin paralelismo.
6. Publica el resumen, las capturas de fallos y el resultado `.xcresult`.
7. Intenta eliminar la rama en un paso `always()`.

La rama se crea desde el proyecto Supabase real, pero todas las escrituras de las pruebas ocurren en la rama efímera. El seed prepara:

- un usuario de email confirmado;
- saldo de Liftr Coins y una mascota activa;
- el artículo `food_baby` del mercado;
- al menos un ejercicio público de fuerza;
- ausencia de una meta semanal de entrenamientos previa.

## Secrets de GitHub

| Secret | Uso |
| --- | --- |
| `SUPABASE_ACCESS_TOKEN` | Crear, consultar y eliminar ramas de preview. |
| `SUPABASE_PROJECT_ID` | Proyecto padre y workdir enlazado. |
| `SUPABASE_DB_PASSWORD` | Leer el esquema padre si la rama queda en `MIGRATIONS_FAILED`. |
| `UI_TEST_EMAIL` | Usuario estable que crea el seed. |
| `UI_TEST_PASSWORD` | Contraseña del usuario; debe tener al menos 8 caracteres. |

El workflow fija el host del pooler en `aws-1-eu-west-1.pooler.supabase.com:5432`. Si el proyecto cambia de región o de endpoint, hay que actualizar `SUPABASE_DB_HOST` y `SUPABASE_DB_PORT` en el workflow.

Las credenciales de la rama se escriben temporalmente en `scripts/ci/.branch.env` y `scripts/ci/.ui-test.env`. Ambos archivos, junto con el dump `scripts/ci/.parent-schema.sql`, están ignorados por Git.

## Cobertura actual

| Clase | Recorrido |
| --- | --- |
| `ExploreTabRegressionTests` | Abre búsqueda/exploración. |
| `NutritionTabRegressionTests` | Carga la pestaña de nutrición. |
| `HomeFeedRegressionTests` | Carga el feed autenticado. |
| `NavigationRobustnessRegressionTests` | Visita todas las pestañas principales sin perder la barra. |
| `AuthSessionRegressionTests` | Inicia sesión manualmente y muestra el perfil. |
| `RegisterValidationRegressionTests` | Rechaza un email de registro inválido. |
| `ForgotPasswordRegressionTests` | Envía el formulario de recuperación. |
| `ProfileMenuRegressionTests` | Abre metas y logros desde perfil. |
| `RegisterFullRegressionTests` | Registra un usuario único y muestra su perfil. |
| `AddWorkoutCardioRegressionTests` | Guarda un entrenamiento de cardio y vuelve al feed. |
| `CreateGoalRegressionTests` | Crea una meta semanal de entrenamientos. |
| `AddWorkoutStrengthRegressionTests` | Guarda fuerza con un ejercicio y repeticiones. |
| `MarketTransactionRegressionTests` | Compra `food_baby` y comprueba la reducción de saldo. |
| `LogoutReloginRegressionTests` | Cierra sesión e inicia sesión de nuevo. |

Las pruebas usan page objects en `LiftrUITests/PageObjects/`. `RegressionTestCase` guarda una captura al fallar y cada paso nombrado aparece como una actividad de XCTest.

## Reproducir una prueba localmente

Requisitos: macOS con Xcode, un simulador iPhone y un backend Supabase de prueba. No apuntes estas pruebas a producción: registro, metas, entrenamientos y compras modifican datos.

Crea `scripts/ci/.ui-test.env`:

```dotenv
SUPABASE_URL=https://example-preview.supabase.co
SUPABASE_ANON_KEY=preview-anon-key
UI_TEST_EMAIL=ui-regression@example.com
UI_TEST_PASSWORD=replace-with-test-password
UI_TEST_SIGNUP_EMAIL=ui-signup-unique@example.com
UI_TEST_SIGNUP_USERNAME=uiregunique
UI_TEST_SIGNUP_PASSWORD=12345678
```

Las cuatro primeras variables son obligatorias. Las tres de registro solo son necesarias para `RegisterFullRegressionTests`; el email y username deben ser únicos para cada ejecución.

Desde la raíz del repositorio:

```bash
eval "$(bash scripts/ci/select-ios-simulator.sh)"

xcodebuild test \
  -project Liftr.xcodeproj \
  -scheme Liftr \
  -destination "platform=iOS Simulator,name=${name}" \
  -maximum-concurrent-test-simulator-destinations 1 \
  -parallel-testing-enabled NO \
  -only-testing:LiftrUITests/MarketTransactionRegressionTests \
  -resultBundlePath TestResults.xcresult
```

Sustituye la clase para aislar otro recorrido. Para reproducir exactamente CI, usa la lista de `-only-testing` del workflow; ejecutar todo `LiftrUITests` también incluye las plantillas y pruebas de lanzamiento que CI excluye.

### Crear el backend efímero local

Para reproducir también el aprovisionamiento de CI, instala Supabase CLI, `jq`, `psql` y `pg_dump`; exporta `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_ID`, `SUPABASE_DB_PASSWORD`, `UI_TEST_EMAIL`, `UI_TEST_PASSWORD` y un `BRANCH_NAME` único. Después:

```bash
bash scripts/ci/supabase-branch-create.sh
bash scripts/ci/supabase-branch-seed-ui-user.sh
set -a
source scripts/ci/.branch.env
set +a
export SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-${ANON_KEY:-}}"
```

Copia esas credenciales y las variables `UI_TEST_*` a `.ui-test.env` antes de ejecutar `xcodebuild`. Elimina siempre la rama al terminar:

```bash
bash scripts/ci/supabase-branch-teardown.sh
```

Una ejecución cancelada o sin credenciales puede no completar el teardown. En ese caso, elimina manualmente `BRANCH_NAME` desde Supabase antes de volver a ejecutar.

## Resultados y diagnóstico

| Salida | Cuándo | Contenido |
| --- | --- | --- |
| GitHub step summary | Siempre que exista `TestResults.xcresult` | Resultado, duración, pasos y mensaje de cada prueba. |
| `ios-ui-screenshots-<run_id>` | Siempre; puede estar vacío | PNG de cada fallo y `report.html`. |
| `ios-ui-visual-report-<run_id>` | Siempre; puede estar vacío | Informe HTML autocontenido. |
| `ios-ui-test-results-<run_id>` | Solo si falla el job | Bundle completo para abrir con Xcode. |

Fallos frecuentes:

- **Missing UI test environment:** falta alguna de `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `UI_TEST_EMAIL` o `UI_TEST_PASSWORD`.
- **`MIGRATIONS_FAILED`:** el script activa el bootstrap del esquema padre; comprueba contraseña, host y versiones de `pg_dump`/`psql`.
- **El seed falla antes de Xcode:** revisa la verificación indicada; el script exige identidad email, mascota activa, RPCs de mercado y ejercicio de fuerza.
- **La app no llega a `uitest.authenticated`:** comprueba primero login y URL de la rama; después revisa el selector de accesibilidad afectado.
- **No hay simulador:** instala un runtime de iOS; `select-ios-simulator.sh` busca varios modelos preferidos y después usa el primer iPhone disponible.

## Mantener la suite

Al añadir un recorrido:

1. Reutiliza `RegressionTestCase` y los page objects existentes.
2. Expón identificadores de accesibilidad estables; no dependas de coordenadas ni de textos localizados cuando exista un identificador.
3. Añade la clase a la lista `-only-testing` del workflow.
4. Actualiza el seed solo si el recorrido necesita un fixture determinista.
5. Añade la clase a la tabla de cobertura de este documento.

Los cambios del seed o de los scripts de rama afectan al entorno de CI completo. Valida que el teardown conserva `BRANCH_NAME` y que ningún archivo `.env` o dump se incluye en el commit.
