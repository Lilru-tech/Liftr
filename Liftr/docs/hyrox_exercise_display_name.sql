-- Run in Supabase SQL editor (or migrate) before relying on custom Hyrox exercise names from the app.
ALTER TABLE hyrox_session_exercises
ADD COLUMN IF NOT EXISTS exercise_display_name text;

COMMENT ON COLUMN hyrox_session_exercises.exercise_display_name IS 'Optional human-readable name for custom/other exercises; when null, label is derived from exercise_code.';

-- If exercise_display_name stays NULL after saving from the app, inspect create_sport_workout_v2 / update_sport_workout_v2:
-- the JSON path p_stats->'exercises' should map each element's "exercise_display_name" into INSERT ... hyrox_session_exercises.
-- The iOS app also PATCHes this column after RPC as a workaround when the function omits the field.

-- Optional backfill for legacy rows (custom + empty name, notes present): first line of notes → display name
-- UPDATE hyrox_session_exercises e
-- SET exercise_display_name = trim(split_part(coalesce(e.notes, ''), E'\n', 1))
-- WHERE e.exercise_code = 'custom'
--   AND (e.exercise_display_name IS NULL OR trim(e.exercise_display_name) = '')
--   AND e.notes IS NOT NULL AND trim(e.notes) <> '';
