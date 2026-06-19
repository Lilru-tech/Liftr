-- Hotfix: si get_group_workout_sessions_leaderboard_v1 ya existe sin SECURITY DEFINER,
-- ejecuta esto en el SQL Editor (no hace falta volver a pegar el cuerpo completo).
-- Útil si la app ve vacío con global+all pero postgres en el editor sí ve filas (RLS).

ALTER FUNCTION public.get_group_workout_sessions_leaderboard_v1(text, text, int, text, text)
  SECURITY DEFINER;

ALTER FUNCTION public.get_group_workout_sessions_leaderboard_v1(text, text, int, text, text)
  SET search_path TO 'public';
