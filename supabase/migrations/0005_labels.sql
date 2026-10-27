-- Tray — the rest of the API: my own profile, and label management.

create or replace function public.me()
returns table (
  id              uuid,
  username        text,
  display_name    text,
  emoji           text,
  phone           text,
  campus_slug     text,
  invisible_until timestamptz
)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name, p.emoji, p.phone,
         c.slug, p.invisible_until
    from public.profiles p
    left join public.campuses c on c.id = p.campus_id
   where p.id = auth.uid();
$$;

create or replace function public.username_available(p_username text)
returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from public.profiles
     where lower(username) = lower(trim(p_username))
       and id is distinct from auth.uid());
$$;

-- Labels are just folders you keep for yourself: "lab group", "floor 12".
create or replace function public.label_list()
returns table (id uuid, name text, color text, member_count integer)
language sql stable security definer set search_path = public as $$
  select l.id, l.name, l.color,
         (select count(*)::integer from public.friend_label_members m
           where m.label_id = l.id)
    from public.friend_labels l
   where l.owner_id = auth.uid()
   order by lower(l.name);
$$;

create or replace function public.create_label(p_name text, p_color text default 'blue')
returns public.friend_labels
language plpgsql security definer set search_path = public as $$
declare v_row public.friend_labels;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if length(trim(p_name)) = 0 then raise exception 'give the group a name'; end if;

  insert into public.friend_labels (owner_id, name, color)
  values (auth.uid(), trim(p_name), coalesce(p_color, 'blue'))
  returning * into v_row;
  return v_row;
exception
  when unique_violation then
    raise exception 'you already have a group called that';
end; $$;

create or replace function public.delete_label(p_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  delete from public.friend_labels where id = p_id and owner_id = auth.uid();
  return found;
end; $$;

create or replace function public.label_members(p_label uuid)
returns table (friend_id uuid)
language sql stable security definer set search_path = public as $$
  select m.friend_id
    from public.friend_label_members m
    join public.friend_labels l on l.id = m.label_id
   where m.label_id = p_label and l.owner_id = auth.uid();
$$;
