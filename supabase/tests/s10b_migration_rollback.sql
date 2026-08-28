\set ON_ERROR_STOP on
begin;
\ir ../migrations/20260817154441_s10b_economy_board_foundation.sql
\ir s10b_economy_board_foundation.sql
rollback;
