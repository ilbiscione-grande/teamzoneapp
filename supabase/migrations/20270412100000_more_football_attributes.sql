-- More football attributes (asked for by the product owner 2026-11-21):
-- defending (interceptions, tackling, marking, blocking, recovery runs) and
-- attacking play (playing with the back to goal, carrying the ball forward).
-- Placed in the list next to their kin.
insert into core.sport_attributes(sport,key,area,sort) values
 ('football','ball_carrying','technical',175),
 ('football','tackling','technical',225),
 ('football','back_to_goal','technical',230),
 ('football','interceptions','tactical',312),
 ('football','marking','tactical',314),
 ('football','blocking','tactical',316),
 ('football','recovery_runs','tactical',375)
on conflict (sport,key) do nothing;
