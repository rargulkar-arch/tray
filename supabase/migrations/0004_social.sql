-- Tray — friends, labels, invites.

-- Look someone up by the number you already have in your phone. Returns at most
-- one row, and only enough to decide whether it is the right person.
create or replace function public.find_by_phone(p_phone text)
returns table (id uuid, display_name text, username text, emoji text, status text)
language plpgsql stable security definer set search_path = public as $$
declare v_norm text := public.normalize_phone(p_phone);
begin
  if v_norm is null then return; end if;
  return query
    select p.id, p.display_name, p.username, p.emoji,
           coalesce((select f.status from public.friendships f
                      where (f.requester = auth.uid() and f.addressee = p.id)
                         or (f.addressee = auth.uid() and f.requester = p.id)),
                    'none')
      from public.profiles p
     where p.phone = v_norm and p.id <> auth.uid();
end; $$;

create or replace function public.find_by_username(p_username text)
returns table (id uuid, display_name text, username text, emoji text, status text)
language plpgsql stable security definer set search_path = public as $$
begin
  return query
    select p.id, p.display_name, p.username, p.emoji,
           coalesce((select f.status from public.friendships f
                      where (f.requester = auth.uid() and f.addressee = p.id)
                         or (f.addressee = auth.uid() and f.requester = p.id)),
                    'none')
      from public.profiles p
     where lower(p.username) = lower(trim(p_username)) and p.id <> auth.uid();
end; $$;

-- Sending a request. If they already asked you, this accepts instead — so two
-- people adding each other at the same time become friends rather than deadlock.
create or replace function public.request_friend(p_user uuid)
returns public.friendships
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_row public.friendships;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if v_uid = p_user then raise exception 'you cannot add yourself'; end if;

  select * into v_row from public.friendships f
   where (f.requester = v_uid and f.addressee = p_user)
      or (f.requester = p_user and f.addressee = v_uid);

  if found then
    if v_row.status = 'accepted' then return v_row; end if;
    -- They asked first. Treat this as the handshake completing.
    if v_row.addressee = v_uid then
      update public.friendships
         set status = 'accepted', responded_at = now()
       where id = v_row.id returning * into v_row;
    end if;
    return v_row;
  end if;

  insert into public.friendships (requester, addressee)
  values (v_uid, p_user) returning * into v_row;
  return v_row;
end; $$;

create or replace function public.respond_friend(p_id uuid, p_accept boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  if p_accept then
    update public.friendships set status = 'accepted', responded_at = now()
     where id = p_id and addressee = v_uid and status = 'pending';
  else
    delete from public.friendships where id = p_id and addressee = v_uid;
  end if;
  return found;
end; $$;

create or replace function public.unfriend(p_user uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  delete from public.friendships f
   where (f.requester = v_uid and f.addressee = p_user)
      or (f.requester = p_user and f.addressee = v_uid);
  delete from public.friend_notify
   where owner_id = v_uid and friend_id = p_user;
  return true;
end; $$;

-- The friends tab: everyone accepted, plus requests waiting on each side.
create or replace function public.friend_list()
returns table (
  friendship_id uuid,
  user_id       uuid,
  display_name  text,
  username      text,
  emoji         text,
  status        text,
  direction     text,      -- 'friend' | 'incoming' | 'outgoing'
  notify_on     boolean,
  label_ids     uuid[]
)
language sql stable security definer set search_path = public as $$
  select f.id,
         other.id, other.display_name, other.username, other.emoji,
         f.status,
         case when f.status = 'accepted'    then 'friend'
              when f.addressee = auth.uid() then 'incoming'
              else                               'outgoing' end,
         exists (select 1 from public.friend_notify n
                  where n.owner_id = auth.uid() and n.friend_id = other.id),
         coalesce((select array_agg(m.label_id)
                     from public.friend_label_members m
                     join public.friend_labels l on l.id = m.label_id
                    where m.friend_id = other.id and l.owner_id = auth.uid()),
                  '{}'::uuid[])
    from public.friendships f
    join public.profiles other
      on other.id = case when f.requester = auth.uid() then f.addressee else f.requester end
   where f.requester = auth.uid() or f.addressee = auth.uid()
   order by (f.status = 'pending') desc, lower(other.display_name);
$$;

create or replace function public.set_notify(p_friend uuid, p_on boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if not public.are_friends(v_uid, p_friend) then
    raise exception 'not friends';
  end if;
  if p_on then
    insert into public.friend_notify (owner_id, friend_id)
    values (v_uid, p_friend) on conflict do nothing;
  else
    delete from public.friend_notify
     where owner_id = v_uid and friend_id = p_friend;
  end if;
  return p_on;
end; $$;

-- ---------------------------------------------------------------- invites

-- "Rohit is asking you to join them at The Eatery." The hall defaults to
-- wherever the sender currently is, which is the only time the ask makes sense.
create or replace function public.send_invite(p_to uuid, p_hall uuid default null)
returns public.invites
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_hall uuid := p_hall; v_row public.invites;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not public.are_friends(v_uid, p_to) then raise exception 'not friends'; end if;

  if v_hall is null then
    select c.hall_id into v_hall from public.checkins c
     where c.user_id = v_uid and c.ended_at is null and c.auto_expires_at > now();
  end if;
  if v_hall is null then
    raise exception 'you need to be at a dining hall to invite someone';
  end if;

  -- Don't let a nervous tap turn into a pile of notifications.
  select * into v_row from public.invites i
   where i.from_user = v_uid and i.to_user = p_to
     and i.response is null and i.created_at > now() - interval '20 minutes';
  if found then return v_row; end if;

  insert into public.invites (from_user, to_user, hall_id)
  values (v_uid, p_to, v_hall) returning * into v_row;
  return v_row;
end; $$;

create or replace function public.respond_invite(p_id uuid, p_response text)
returns public.invites
language plpgsql security definer set search_path = public as $$
declare v_row public.invites;
begin
  if p_response not in ('omw','in_a_bit','already_ate','cant') then
    raise exception 'unknown response';
  end if;
  update public.invites
     set response = p_response, responded_at = now()
   where id = p_id and to_user = auth.uid() and response is null
  returning * into v_row;
  if not found then raise exception 'invite not found or already answered'; end if;
  return v_row;
end; $$;

create or replace function public.invite_feed()
returns table (
  id           uuid,
  direction    text,     -- 'incoming' | 'outgoing'
  other_id     uuid,
  other_name   text,
  other_emoji  text,
  hall_id      uuid,
  hall_name    text,
  created_at   timestamptz,
  expires_at   timestamptz,
  response     text,
  responded_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select i.id,
         case when i.to_user = auth.uid() then 'incoming' else 'outgoing' end,
         other.id, other.display_name, other.emoji,
         h.id, h.name,
         i.created_at, i.expires_at, i.response, i.responded_at
    from public.invites i
    join public.profiles other
      on other.id = case when i.to_user = auth.uid() then i.from_user else i.to_user end
    join public.dining_halls h on h.id = i.hall_id
   where (i.to_user = auth.uid() or i.from_user = auth.uid())
     and i.created_at > now() - interval '12 hours'
   order by i.created_at desc;
$$;

-- Everything worth waking someone up for since they last looked. The app polls
-- this and raises local notifications; a server push would call the same query.
create or replace function public.alerts_since(p_since timestamptz)
returns table (kind text, at timestamptz, other_name text, hall_name text, ref uuid)
language sql stable security definer set search_path = public as $$
  -- Friends you asked to be told about, arriving somewhere.
  select 'arrival', c.started_at, p.display_name, h.name, c.id
    from public.checkins c
    join public.profiles p      on p.id = c.user_id
    join public.dining_halls h  on h.id = c.hall_id
    join public.friend_notify n on n.friend_id = p.id and n.owner_id = auth.uid()
   where c.started_at > p_since
     and c.ended_at is null
     and public.is_visible(p.id)
  union all
  -- Someone asking you to come eat.
  select 'invite', i.created_at, p.display_name, h.name, i.id
    from public.invites i
    join public.profiles p     on p.id = i.from_user
    join public.dining_halls h on h.id = i.hall_id
   where i.to_user = auth.uid() and i.created_at > p_since and i.response is null
  union all
  -- Someone answering the ask you sent.
  select 'reply', i.responded_at, p.display_name, i.response, i.id
    from public.invites i
    join public.profiles p on p.id = i.to_user
   where i.from_user = auth.uid() and i.responded_at > p_since
  order by 2 desc;
$$;

-- ---------------------------------------------------------------- labels

create or replace function public.set_label_member(
  p_label uuid, p_friend uuid, p_on boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.friend_labels
                  where id = p_label and owner_id = auth.uid()) then
    raise exception 'label not found';
  end if;
  if p_on then
    insert into public.friend_label_members (label_id, friend_id)
    values (p_label, p_friend) on conflict do nothing;
  else
    delete from public.friend_label_members
     where label_id = p_label and friend_id = p_friend;
  end if;
  return p_on;
end; $$;
