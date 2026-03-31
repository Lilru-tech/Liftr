-- Run in Supabase SQL editor (or migrate) before relying on custom Hyrox exercise names from the app.
ALTER TABLE hyrox_session_exercises
ADD COLUMN IF NOT EXISTS exercise_display_name text;

COMMENT ON COLUMN hyrox_session_exercises.exercise_display_name IS 'Optional human-readable name for custom/other exercises; when null, label is derived from exercise_code.';
