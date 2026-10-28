-- Protein and nutritional powders move from Other to Protein Foods, in a subgroup of their own. WWEIA files them
-- under Other, but people look for them beside the other protein foods. The Other group and subgroup stay: they
-- are where uncategorized foods show.

update public.food_subgroups set position = position + 1 where position >= 13;
insert into public.food_subgroups (id, group_id, name, position, source) values
  ('protein-and-nutritional-powders', 'protein-foods', 'Protein and Nutritional Powders', 13, 'nutrimeter');

update public.food_categories set position = position + 1 where position >= 28;
update public.food_categories
set subgroup_id = 'protein-and-nutritional-powders', position = 28,
    note = 'WWEIA files this under Other; Nutrimeter files it under Protein Foods.'
where id = 'protein-and-nutritional-powders';
