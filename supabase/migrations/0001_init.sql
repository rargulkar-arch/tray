-- Tray — schema
-- Presence-only dining hall app. Friends see WHERE you are eating and WHEN you got
-- there, nothing else. Run this once in the Supabase SQL editor.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- campuses

create table public.campuses (
  id         uuid primary key default gen_random_uuid(),
  slug       text unique not null,
  name       text not null,
  created_at timestamptz not null default now()
);

create table public.dining_halls (
  id         uuid primary key default gen_random_uuid(),
  campus_id  uuid not null references public.campuses(id) on delete cascade,
  name       text not null,
  building   text,
  -- Geofence. radius_m is deliberately tight: Stetson East and Stetson West are
  -- ~50m apart, so overlapping circles are resolved client-side by nearest-wins.
  lat        double precision not null,
  lng        double precision not null,
  radius_m   integer not null default 60,
  sort_order integer not null default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create index dining_halls_campus_idx on public.dining_halls(campus_id) where active;

-- Makes seed.sql safe to run more than once.
create unique index dining_halls_campus_name_idx on public.dining_halls(campus_id, name);

-- ---------------------------------------------------------------- profiles

create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  phone           text unique,
  username        text not null,
  display_name    text not null,
  emoji           text not null default '🍜',
  campus_id       uuid references public.campuses(id),
  -- Invisible mode. NULL = visible. "Invisible today" sets this to local midnight.
  invisible_until timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create unique index profiles_username_lower_idx on public.profiles(lower(username));
create index profiles_phone_idx on public.profiles(phone);

-- ---------------------------------------------------------------- friendships

create table public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester    uuid not null references public.profiles(id) on delete cascade,
  addressee    uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending','accepted')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  constraint no_self_friendship check (requester <> addressee)
);

-- One edge per pair, in either direction.
create unique index friendships_pair_idx
  on public.friendships (least(requester, addressee), greatest(requester, addressee));

create index friendships_requester_idx on public.friendships(requester);
create index friendships_addressee_idx on public.friendships(addressee);

-- ---------------------------------------------------------------- labels

create table public.friend_labels (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  name       text not null,
  color      text not null default 'blue',
  created_at timestamptz not null default now()
);

create unique index friend_labels_owner_name_idx
  on public.friend_labels(owner_id, lower(name));

create table public.friend_label_members (
  label_id  uuid not null references public.friend_labels(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  primary key (label_id, friend_id)
);

-- ---------------------------------------------------------------- check-ins

create table public.checkins (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  hall_id         uuid not null references public.dining_halls(id) on delete cascade,
  started_at      timestamptz not null default now(),
  ended_at        timestamptz,
  source          text not null default 'auto' check (source in ('auto','manual')),
  -- Safety net so a missed geofence exit does not leave someone "eating" forever.
  auto_expires_at timestamptz not null default now() + interval '3 hours'
);

-- At most one open check-in per person.
create unique index checkins_one_open_idx on public.checkins(user_id) where ended_at is null;
create index checkins_hall_open_idx on public.checkins(hall_id) where ended_at is null;
create index checkins_user_started_idx on public.checkins(user_id, started_at desc);

-- ---------------------------------------------------------------- invites

create table public.invites (
  id           uuid primary key default gen_random_uuid(),
  from_user    uuid not null references public.profiles(id) on delete cascade,
  to_user      uuid not null references public.profiles(id) on delete cascade,
  hall_id      uuid not null references public.dining_halls(id) on delete cascade,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '90 minutes',
  response     text check (response in ('omw','in_a_bit','already_ate','cant')),
  responded_at timestamptz,
  constraint no_self_invite check (from_user <> to_user)
);

create index invites_to_user_idx on public.invites(to_user, created_at desc);
create index invites_from_user_idx on public.invites(from_user, created_at desc);

-- ------------------------------------------------- per-friend arrival alerts

-- A row here means: tell me when this friend checks in. Private to the owner.
create table public.friend_notify (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  friend_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id)
);

-- Device push tokens. Unused until there is a paid Apple developer account;
-- the table exists so turning push on later is a server change only.
create table public.device_tokens (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  token      text not null,
  platform   text not null default 'ios',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);
