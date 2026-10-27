-- Tray — helper predicates and row level security.
-- These two helpers are SECURITY DEFINER so that RLS policies can ask
-- "are these two people friends?" without re-entering RLS and recursing.

create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester = a and f.addressee = b)
        or (f.requester = b and f.addressee = a))
  );
$$;

-- Visible means: not currently hiding. Invisible mode is checked on every read,
-- so flipping it mid-meal removes you from your friends' lists immediately.
create or replace function public.is_visible(u uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select p.invisible_until is null or p.invisible_until <= now()
       from public.profiles p where p.id = u),
    false);
$$;

-- "Do I have any relationship at all with this person" — used so a pending
-- request can show you the name and face of whoever sent it.
create or replace function public.has_edge(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where (f.requester = a and f.addressee = b)
       or (f.requester = b and f.addressee = a)
  );
$$;

-- ---------------------------------------------------------------- enable RLS

alter table public.campuses             enable row level security;
alter table public.dining_halls         enable row level security;
alter table public.profiles             enable row level security;
alter table public.friendships          enable row level security;
alter table public.friend_labels        enable row level security;
alter table public.friend_label_members enable row level security;
alter table public.checkins             enable row level security;
alter table public.invites              enable row level security;
alter table public.friend_notify        enable row level security;
alter table public.device_tokens        enable row level security;

-- Campuses and halls are public reference data to any signed-in user.
create policy campuses_read on public.campuses
  for select to authenticated using (true);

create policy halls_read on public.dining_halls
  for select to authenticated using (true);

-- Profiles: yourself, your friends, and anyone with a pending request either way.
create policy profiles_read on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.has_edge(auth.uid(), id));

create policy profiles_insert on public.profiles
  for insert to authenticated with check (id = auth.uid());

create policy profiles_update on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Friendships: only the two people involved ever see the row.
create policy friendships_read on public.friendships
  for select to authenticated
  using (requester = auth.uid() or addressee = auth.uid());

create policy friendships_insert on public.friendships
  for insert to authenticated with check (requester = auth.uid());

-- Only the person who received the request can accept it.
create policy friendships_update on public.friendships
  for update to authenticated
  using (addressee = auth.uid()) with check (addressee = auth.uid());

-- Either side can unfriend.
create policy friendships_delete on public.friendships
  for delete to authenticated
  using (requester = auth.uid() or addressee = auth.uid());

-- Labels are a private organising tool. The people in them never learn they exist.
create policy labels_all on public.friend_labels
  for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy label_members_all on public.friend_label_members
  for all to authenticated
  using (exists (select 1 from public.friend_labels l
                  where l.id = label_id and l.owner_id = auth.uid()))
  with check (exists (select 1 from public.friend_labels l
                  where l.id = label_id and l.owner_id = auth.uid()));

-- Check-ins: yours always; a friend's only while they are visible.
-- This is the whole privacy model of the app, in one policy.
create policy checkins_read on public.checkins
  for select to authenticated
  using (
    user_id = auth.uid()
    or (public.are_friends(auth.uid(), user_id) and public.is_visible(user_id))
  );

create policy checkins_write on public.checkins
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Invites: sender and recipient.
create policy invites_read on public.invites
  for select to authenticated
  using (from_user = auth.uid() or to_user = auth.uid());

create policy invites_insert on public.invites
  for insert to authenticated
  with check (from_user = auth.uid() and public.are_friends(auth.uid(), to_user));

-- Only the recipient can answer.
create policy invites_update on public.invites
  for update to authenticated
  using (to_user = auth.uid()) with check (to_user = auth.uid());

create policy notify_all on public.friend_notify
  for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy tokens_all on public.device_tokens
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
