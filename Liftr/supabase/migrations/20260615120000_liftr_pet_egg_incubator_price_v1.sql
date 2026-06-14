begin;

update public.pet_market_items
set price = 2000
where item_type in ('pet_egg', 'incubator');

commit;
