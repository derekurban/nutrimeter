-- The admin site (service role) reads tables directly but writes only through the functions above, which check
-- and log every change. Say so explicitly instead of relying on default privileges: branches created later (like
-- `staging`) don't grant the API roles anything by default, and older ones grant everything.
grant usage on schema public to service_role;
grant select on all tables in schema public to service_role;
revoke insert, update, delete, truncate on all tables in schema public from service_role;
