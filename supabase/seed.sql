-- Tray — Northeastern Boston campus.
-- Coordinates come from OpenStreetMap building/venue nodes, not from guessing
-- at street addresses. Radii are tight on purpose: Stetson East and Stetson
-- West are about 50m apart, so their circles would otherwise overlap and both
-- fire. The app resolves an overlap by picking the nearest hall, but keeping
-- the radii small means that rarely has to happen.

insert into public.campuses (slug, name)
values ('neu', 'Northeastern University')
on conflict (slug) do nothing;

insert into public.dining_halls (campus_id, name, building, lat, lng, radius_m, sort_order)
select c.id, v.name, v.building, v.lat, v.lng, v.radius_m, v.sort_order
  from public.campuses c,
       (values
         ('The Eatery',      'Stetson East',          42.3413237, -71.0901801, 45, 1),
         ('Stetson West',    'Outtakes & Kigo Kitchen', 42.3409303, -71.0904858, 45, 2),
         ('United Table',    'International Village', 42.3354102, -71.0889895, 70, 3),
         ('Campus Roots',    '60 Belvidere',          42.3461167, -71.0855153, 60, 4),
         ('Curry Food Court','Curry Student Center',  42.3391141, -71.0875611, 70, 5)
       ) as v(name, building, lat, lng, radius_m, sort_order)
 where c.slug = 'neu'
on conflict (campus_id, name) do update
  set lat = excluded.lat, lng = excluded.lng, radius_m = excluded.radius_m,
      building = excluded.building, sort_order = excluded.sort_order, active = true;
