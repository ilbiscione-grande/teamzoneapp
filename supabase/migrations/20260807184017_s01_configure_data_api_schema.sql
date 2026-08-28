-- S01 exposes only the authenticated command/query API. The anonymous
-- public_api schema is intentionally deferred until its own delivery slice.
alter role authenticator set pgrst.db_schemas = 'api';

notify pgrst, 'reload config';
