\set ON_ERROR_STOP on
begin;
\ir ../migrations/20260817155109_s10b_economy_commands.sql

do $$
begin
 if has_function_privilege('anon','api.get_economy(uuid)','execute') then raise exception 'anon economy API exposed'; end if;
 if not has_function_privilege('authenticated','api.get_economy(uuid)','execute') then raise exception 'authenticated economy API missing'; end if;
 if has_function_privilege('authenticated','internal.require_economy_actor(uuid,text)','execute') then raise exception 'internal economy boundary exposed'; end if;
end$$;

rollback;
