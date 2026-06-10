begin;

alter table public.pet_types
  add column if not exists image_egg text,
  add column if not exists image_baby text,
  add column if not exists image_kid text,
  add column if not exists image_teen text,
  add column if not exists image_adult text,
  add column if not exists image_elder text;

update public.pet_types
set
  image_egg = format(
    'https://rjzhaafvkxmvlnpsikbi.supabase.co/storage/v1/object/public/pets/%s_egg.png',
    name
  ),
  image_baby = format(
    'https://rjzhaafvkxmvlnpsikbi.supabase.co/storage/v1/object/public/pets/%s_baby.png',
    name
  ),
  image_kid = format(
    'https://rjzhaafvkxmvlnpsikbi.supabase.co/storage/v1/object/public/pets/%s_kid.png',
    name
  ),
  image_teen = format(
    'https://rjzhaafvkxmvlnpsikbi.supabase.co/storage/v1/object/public/pets/%s_teen.png',
    name
  ),
  image_adult = format(
    'https://rjzhaafvkxmvlnpsikbi.supabase.co/storage/v1/object/public/pets/%s_adult.png',
    name
  ),
  image_elder = format(
    'https://rjzhaafvkxmvlnpsikbi.supabase.co/storage/v1/object/public/pets/%s_elder.png',
    name
  );

create or replace function public.liftr_pet_image_url_for_stage(p_pet_type text, p_stage text)
returns text
language sql
stable
set search_path to public
as $$
  select case lower(coalesce(p_stage, 'egg'))
    when 'egg' then pt.image_egg
    when 'baby' then pt.image_baby
    when 'kid' then pt.image_kid
    when 'teen' then pt.image_teen
    when 'adult' then pt.image_adult
    when 'elder' then pt.image_elder
    else pt.image_egg
  end
  from public.pet_types pt
  where pt.name = p_pet_type;
$$;

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
  v_pet_type text;
  v_image_url text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  perform public.liftr_hatch_pet_egg_for_user(v_user_id);

  select to_jsonb(pi.*) into v_pet
  from public.pet_instances pi
  where pi.user_id = v_user_id
    and pi.is_active = true
  limit 1;

  select coalesce(jsonb_agg(to_jsonb(ui.*)), '[]'::jsonb) into v_inventory
  from public.user_inventory ui
  where ui.user_id = v_user_id
    and ui.quantity > 0;

  if v_pet is null then
    return jsonb_build_object(
      'pet', null,
      'stats', null,
      'inventory', v_inventory,
      'xp_required', 0,
      'can_evolve', false
    );
  end if;

  v_stage := v_pet->>'evolution_stage';
  v_pet_type := v_pet->>'pet_type';
  v_image_url := public.liftr_pet_image_url_for_stage(v_pet_type, v_stage);

  if v_image_url is not null then
    v_pet := jsonb_set(v_pet, '{image_url}', to_jsonb(v_image_url), true);
  end if;

  select to_jsonb(ps.*) into v_stats
  from public.pet_instance_stats ps
  where ps.pet_instance_id = (v_pet->>'id')::uuid;

  select required_exp into v_required_exp
  from public.pet_levels
  where level = (v_pet->>'current_level')::integer;

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
