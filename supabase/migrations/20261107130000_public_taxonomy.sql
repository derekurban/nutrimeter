-- The food taxonomy (USDA WWEIA groups, subgroups and categories, with their pictures) is public and cosmetic: the
-- same in every environment, and its pictures already sit in the public `taxonomy-art` bucket. The app reads it
-- without an account, so a phone that is not signed in still shows each food's picture and can file a product it
-- reads. Read only; everything else in the catalogue still needs a signed-in user.

grant select on public.food_groups, public.food_subgroups, public.food_categories to anon;
create policy food_groups_read_anon on public.food_groups for select to anon using (true);
create policy food_subgroups_read_anon on public.food_subgroups for select to anon using (true);
create policy food_categories_read_anon on public.food_categories for select to anon using (true);
