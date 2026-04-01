# Conectar Cursor a la base de datos (Supabase / PostgreSQL)

Puedes ver y consultar la base de datos desde Cursor con una extensión, sin depender de DBVisualizer.

## 1. Obtener la conexión PostgreSQL de Supabase (Connection Pooler)

Para SQLTools desde Cursor hay que usar el **Connection Pooler** (la conexión directa suele dar timeout). La región del host debe coincidir con tu proyecto.

1. Entra en [Supabase Dashboard](https://supabase.com/dashboard) → tu proyecto.
2. **Project Settings** (engranaje) → **Database**.
3. Baja hasta **Connection string** y abre la pestaña **Connection pooling** (o "Transaction").
4. Elige **URI** y copia la URL. Será algo como:
   `postgresql://postgres.rjzhaafvkxmvlnpsikbi:[PASSWORD]@aws-0-**eu-west-1**.pooler.supabase.com:6543/postgres`
5. Del URI necesitas:
   - **Host (server):** solo el dominio, ej. `aws-0-eu-west-1.pooler.supabase.com` (la parte entre `@` y `:6543`). **La región (eu-west-1, us-east-1, etc.) depende de tu proyecto**; debe ser exactamente la que muestra el Dashboard.
   - **Port:** `6543` (Transaction pooler).
   - **Database:** `postgres`.
   - **Username:** `postgres.rjzhaafvkxmvlnpsikbi` (o el que salga en el URI).
   - **Password:** la contraseña de la base de datos.

Si pones una región equivocada en el host, verás "Tenant or user not found". Usa siempre el host que muestra tu Dashboard.

## 2. Instalar extensión en Cursor

**Opción A: SQLTools (recomendada)**

1. En Cursor: **Extensions** (⌘⇧X) → busca **SQLTools** → Instalar.
2. Busca **SQLTools PostgreSQL/Cockroach Driver** → Instalar.
3. Recarga la ventana si te lo pide.

**Opción B: PostgreSQL (Microsoft)**

1. **Extensions** → busca **PostgreSQL** (publicada por Microsoft) → Instalar.

## 3. Añadir la conexión

### Con SQLTools

1. Abre la barra lateral y haz clic en el icono **SQLTools** (base de datos).
2. **Add new connection** → **PostgreSQL**.
3. Rellena con los datos de Supabase (Database):
   - **Host**: el host de la connection string (ej. `aws-0-eu-central-1.pooler.supabase.com`).
   - **Port**: `5432` (direct) o `6543` (pooler).
   - **Database**: `postgres`.
   - **Username**: `postgres.[tu-project-ref]`.
   - **Password**: la contraseña de la base de datos.
4. En **Advanced** activa **SSL** (Supabase usa SSL).
5. **Test connection** → **Save connection**.

### Con PostgreSQL (Microsoft)

1. Clic en el icono del elefante en la barra lateral.
2. **Add Connection** e introduce host, puerto, base de datos, usuario y contraseña (SSL si lo pide).

## 4. Uso

- **SQLTools**: expande la conexión en el árbol → tablas, vistas, etc. Clic derecho en una tabla para ver datos o generar SELECT. Abre un archivo `.sql` y ejecuta la query (Run on connection).
- **PostgreSQL (Microsoft)**: explora objetos en el árbol, abre el editor de consultas y ejecuta SQL.

## Seguridad

- No guardes la contraseña de la base de datos en el repositorio.
- Puedes usar **Connection string** en un archivo local no versionado (ej. `.env` o configuración de la extensión solo en tu máquina).
