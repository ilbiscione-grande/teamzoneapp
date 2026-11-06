-- A club's web address is at least three characters, so that no club can take
-- a short address the site uses itself, such as /en. Team addresses sit under
-- the club's and keep their own rule.
alter table core.club_publication_settings
  drop constraint club_publication_settings_slug_check;
alter table core.club_publication_settings
  add constraint club_publication_settings_slug_check check (
    slug = lower(slug)
    and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
    and length(slug) between 3 and 80
  );
