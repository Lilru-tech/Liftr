begin;

create or replace function public.liftr_combat_pet_side_json(
  p_user_id uuid,
  p_username text,
  p_instance_id uuid,
  p_pet_type text,
  p_custom_name text,
  p_evolution_stage text,
  p_current_level integer,
  p_rarity text,
  p_health integer,
  p_strength integer,
  p_defense integer,
  p_speed integer,
  p_intelligence integer,
  p_agility integer,
  p_stamina integer,
  p_critical_rate integer,
  p_resistance integer,
  p_exploration integer,
  p_happiness integer
)
returns jsonb
language plpgsql
stable
set search_path to public
as $$
declare
  v_image_url text;
  v_name text;
  v_battle_health integer;
begin
  v_image_url := public.liftr_pet_image_url_for_stage(p_pet_type, p_evolution_stage);
  v_name := coalesce(nullif(trim(p_custom_name), ''), initcap(replace(p_pet_type, '_', ' ')));
  v_battle_health := public.liftr_combat_battle_hp_v1(p_health);

  return jsonb_build_object(
    'user_id', p_user_id,
    'username', p_username,
    'pet', jsonb_build_object(
      'id', p_instance_id,
      'custom_name', p_custom_name,
      'pet_type', p_pet_type,
      'evolution_stage', p_evolution_stage,
      'current_level', p_current_level,
      'rarity', p_rarity,
      'image_url', v_image_url,
      'name', v_name
    ),
    'stats', jsonb_build_object(
      'health', v_battle_health,
      'strength', p_strength,
      'defense', p_defense,
      'speed', p_speed,
      'intelligence', p_intelligence,
      'agility', p_agility,
      'stamina', p_stamina,
      'critical_rate', p_critical_rate,
      'resistance', p_resistance,
      'exploration', p_exploration,
      'happiness', p_happiness
    )
  );
end;
$$;

commit;
