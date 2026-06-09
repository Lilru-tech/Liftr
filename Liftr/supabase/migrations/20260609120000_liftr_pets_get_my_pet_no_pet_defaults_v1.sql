begin;

create or replace function public.get_my_pet_v1()
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_pet jsonb;
  v_stats jsonb;
  v_inventory jsonb;
  v_required_exp integer;
  v_can_evolve boolean := false;
  v_stage text;
  v_level integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select to_jsonb(pi.*) into v_pet
  from public.pet_instances pi
  where pi.user_id = v_user_id
    and pi.is_active = true
  limit 1;

  if v_pet is null then
    return jsonb_build_object(
      'pet', null,
      'stats', null,
      'inventory', '[]'::jsonb,
      'xp_required', 0,
      'can_evolve', false
    );
  end if;

  select to_jsonb(ps.*) into v_stats
  from public.pet_instance_stats ps
  where ps.pet_instance_id = (v_pet->>'id')::uuid;

  select coalesce(jsonb_agg(to_jsonb(ui.*)), '[]'::jsonb) into v_inventory
  from public.user_inventory ui
  where ui.user_id = v_user_id
    and ui.quantity > 0;

  select required_exp into v_required_exp
  from public.pet_levels
  where level = (v_pet->>'current_level')::integer;

  v_stage := v_pet->>'evolution_stage';
  v_level := (v_pet->>'current_level')::integer;

  v_can_evolve := case lower(v_stage)
    when 'baby' then v_level >= 25
    when 'kid' then v_level >= 50
    when 'teen' then v_level >= 75
    when 'adult' then v_level >= 100
    else false
  end;

  return jsonb_build_object(
    'pet', v_pet,
    'stats', v_stats,
    'inventory', v_inventory,
    'xp_required', coalesce(v_required_exp, 0),
    'can_evolve', v_can_evolve
  );
end;
$$;

commit;
