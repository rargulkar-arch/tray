-- Tray — the API surface the app actually calls.
-- Everything the client does goes through one of these, so the rules about
-- who may see what live in the database rather than in the phone.

-- Phone numbers arrive from humans in a dozen formats. Store and compare E.164.
create or replace function public.normalize_phone(p text)
returns text
language plpgsql immutable as $$
declare d text;
begin
  if p is null then return null; end if;
  d := regexp_replace(p, '[^0-9]', '', 'g');
  if length(d) = 10 then return '+1' || d; end if;
  if length(d) = 11 and left(d, 1) = '1' then return '+' || d; end if;
  if length(d) between 8 and 15 then return '+' || d; end if;
  return null;
end; $$;

-- Called once after the SMS code is accepted. Idempotent, so a retry is safe.
create or replace function public.bootstrap_profile(
  p_username text, p_display_name text, p_emoji text default '🍜',
  p_campus_slug text default 'neu')
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_phone  text;
  v_campus uuid;
  v_row    public.profiles;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  if length(trim(p_username)) < 2 then
    raise exception 'username must be at least 2 characters';
  end if;
  if p_username !~ '^[A-Za-z0-9_.]+$' then
    raise exception 'username may only contain letters, numbers, _ and .';
  end if;

  select u.phone into v_phone from auth.users u where u.id = v_uid;
  select c.id into v_campus from public.campuses c where c.slug = p_campus_slug;

  insert into public.profiles (id, phone, username, display_name, emoji, campus_id)
  values (v_uid,
          public.normalize_phone(v_phone),
          trim(p_username),
          coalesce(nullif(trim(p_display_name), ''), trim(p_username)),
          coalesce(nullif(p_emoji, ''), '🍜'),
          v_campus)
  on conflict (id) do update
    set username     = excluded.username,
        display_name = coalesce(excluded.display_name, public.profiles.display_name),
        emoji        = excluded.emoji,
        campus_id    = coalesce(excluded.campus_id, public.profiles.campus_id),
        updated_at   = now()
  returning * into v_row;

  return v_row;
exception
  when unique_violation then
    raise exception 'that username is taken';
end; $$;

-- ---------------------------------------------------------------- presence

-- Arriving somewhere. Idempotent: walking past a geofence twice is not an event.
create or replace function public.check_in(p_hall uuid, p_source text default 'auto')
returns public.checkins
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_open public.checkins; v_row public.checkins;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_open from public.checkins
   where user_id = v_uid and ended_at is null;

  if found then
    -- Same hall: nothing happened, keep the original arrival time.
    if v_open.hall_id = p_hall and v_open.auto_expires_at > now() then
      return v_open;
    end if;
    update public.checkins set ended_at = now() where id = v_open.id;
  end if;

  insert into public.checkins (user_id, hall_id, source)
  values (v_uid, p_hall, coalesce(p_source, 'auto'))
  returning * into v_row;

  return v_row;
end; $$;

create or replace function public.check_out()
returns integer
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_n integer;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  update public.checkins set ended_at = now()
   where user_id = v_uid and ended_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end; $$;

-- The home screen: which friends are eating right now, and where.
-- Invisible friends and expired check-ins are filtered out here, not on the phone.
create or replace function public.now_feed()
returns table (
  user_id      uuid,
  display_name text,
  username     text,
  emoji        text,
  hall_id      uuid,
  hall_name    text,
  started_at   timestamptz,
  notify_on    boolean,
  label_ids    uuid[]
)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, p.username, p.emoji,
         h.id, h.name, c.started_at,
         exists (select 1 from public.friend_notify n
                  where n.owner_id = auth.uid() and n.friend_id = p.id),
         coalesce((select array_agg(m.label_id)
                     from public.friend_label_members m
                     join public.friend_labels l on l.id = m.label_id
                    where m.friend_id = p.id and l.owner_id = auth.uid()),
                  '{}'::uuid[])
    from public.checkins c
    join public.profiles p     on p.id = c.user_id
    join public.dining_halls h on h.id = c.hall_id
   where c.ended_at is null
     and c.auto_expires_at > now()
     and public.are_friends(auth.uid(), p.id)
     and public.is_visible(p.id)
   order by c.started_at desc;
$$;

-- My own current state, so the app can show "you're at The Eatery" without
-- trusting whatever the phone last remembered.
create or replace function public.my_checkin()
returns table (id uuid, hall_id uuid, hall_name text, started_at timestamptz, source text)
language sql stable security definer set search_path = public as $$
  select c.id, h.id, h.name, c.started_at, c.source
    from public.checkins c
    join public.dining_halls h on h.id = c.hall_id
   where c.user_id = auth.uid() and c.ended_at is null and c.auto_expires_at > now();
$$;

-- How busy each hall is, counted across everyone on Tray, not just your friends.
-- Deliberately bucketed: an exact count in a half-empty hall would identify people.
create or replace function public.hall_busyness()
returns table (hall_id uuid, bucket text, headcount integer)
language sql stable security definer set search_path = public as $$
  select h.id,
         case
           when count(c.id) = 0            then 'empty'
           when count(c.id) < 5            then 'a few'
           when count(c.id) < 15           then 'some'
           when count(c.id) < 40           then 'busy'
           else                                 'packed'
         end,
         -- Only expose a number once the crowd is big enough to hide in.
         case when count(c.id) >= 5 then count(c.id)::integer else 0 end
    from public.dining_halls h
    left join public.checkins c
           on c.hall_id = h.id and c.ended_at is null and c.auto_expires_at > now()
   where h.active
   group by h.id;
$$;

create or replace function public.set_invisible(p_until timestamptz)
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare v_row public.profiles;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update public.profiles set invisible_until = p_until, updated_at = now()
   where id = auth.uid() returning * into v_row;
  return v_row;
end; $$;
