-- The preceding migration changes the exposed schema configuration. PostgREST
-- reloads configuration and its function catalog through separate signals.
notify pgrst, 'reload schema';
