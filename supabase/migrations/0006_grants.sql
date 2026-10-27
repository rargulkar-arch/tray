-- Tray — lock the API to signed-in users.
--
-- Postgres grants EXECUTE on new functions to PUBLIC, which includes Supabase's
-- `anon` role. Most of these functions return nothing useful without an
-- auth.uid(), but hall_busyness would happily tell the open internet how many
-- people are in each dining hall. Close the door rather than rely on that.

do $$
declare fn record;
begin
  for fn in
    select p.oid::regprocedure as signature
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'are_friends','is_visible','has_edge','normalize_phone',
         'bootstrap_profile','me','username_available',
         'check_in','check_out','now_feed','my_checkin','hall_busyness','set_invisible',
         'find_by_phone','find_by_username','request_friend','respond_friend','unfriend',
         'friend_list','set_notify','send_invite','respond_invite','invite_feed',
         'alerts_since','label_list','create_label','delete_label','label_members',
         'set_label_member')
  loop
    execute format('revoke all on function %s from public, anon', fn.signature);
    execute format('grant execute on function %s to authenticated', fn.signature);
  end loop;
end $$;

-- Reference data is readable by signed-in users only; RLS already says so, but
-- the table grants should agree.
revoke all on public.campuses, public.dining_halls from anon;
grant select on public.campuses, public.dining_halls to authenticated;
