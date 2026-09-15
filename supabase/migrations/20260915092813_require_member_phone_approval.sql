-- Existing pilot upgrade. Existing verified members keep access; pending players must confirm their number.
alter table public.members add column verification_code text not null default upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create or replace function private.require_verified_member()
returns void language plpgsql security definer set search_path = '' as $$
declare m public.members%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into m from public.members where auth_user_id=auth.uid();
  if m.id is null then raise exception 'NOT_CLUB_MEMBER'; end if;
  if m.verification_status not in ('AdminVerified','OtpVerified') then raise exception 'MEMBER_VERIFICATION_REQUIRED'; end if;
end $$;
revoke all on function private.require_verified_member() from public, anon, authenticated;

create or replace function public.normalize_mobile(p_mobile text)
returns text language sql immutable set search_path = '' as $$
  with x as (select regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g') d, trim(coalesce(p_mobile,'')) raw)
  select case when raw !~ '^[+]?[0-9 () .-]+$' then null
    when d ~ '^[6-9][0-9]{9}$' and raw !~ '^[+]' then '+91'||d
    when d ~ '^91[6-9][0-9]{9}$' then '+'||d
    when d ~ '^(971|966)5[0-9]{8}$' then '+'||d
    when d ~ '^(974|968|965|973)[0-9]{8}$' then '+'||d
    else null end from x
$$;

create or replace function public.get_my_membership()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m public.members%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into m from public.members where auth_user_id=auth.uid();
  if m.id is null then return null; end if;
  return jsonb_build_object('clubId',m.club_id,'name',m.name,'mobileNumber',m.mobile_number,
    'verificationStatus',m.verification_status,'verificationCode',case when m.verification_status='Unverified' then m.verification_code else null end);
end $$;
revoke all on function public.get_my_membership() from public, anon;
grant execute on function public.get_my_membership() to authenticated;

create or replace function public.pilot_join(p_invite_code text,p_name text,p_mobile text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.clubs%rowtype; m public.members%rowtype; phone text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_name is null or length(trim(p_name)) not between 1 and 80 then raise exception 'NAME_REQUIRED'; end if;
  phone:=public.normalize_mobile(p_mobile);
  if phone is null then raise exception 'INVALID_MOBILE'; end if;
  select cl.* into c from public.club_invites i join public.clubs cl on cl.id=i.club_id
    where i.code=p_invite_code and i.is_active and (i.expires_at is null or i.expires_at>now()) limit 1;
  if c.id is null then raise exception 'INVALID_INVITE'; end if;
  -- Serialize requests and never elect an administrator from an unauthenticated phone claim.
  perform 1 from public.clubs where id=c.id for update;
  if not exists(select 1 from public.members where club_id=c.id and role='Admin' and verification_status in ('AdminVerified','OtpVerified')) then
    raise exception 'CLUB_ADMIN_SETUP_REQUIRED';
  end if;
  select * into m from public.members where auth_user_id=auth.uid() for update;
  if m.id is not null and m.club_id<>c.id then raise exception 'ALREADY_IN_ANOTHER_CLUB'; end if;
  if m.id is not null and m.verification_status in ('AdminVerified','OtpVerified') then return public.get_my_membership(); end if;
  if exists(select 1 from public.members where club_id=c.id and mobile_number=phone and id is distinct from m.id) then
    raise exception 'PHONE_ALREADY_REGISTERED';
  end if;
  if m.id is null then
    insert into public.members(club_id,auth_user_id,name,mobile_number,role,verification_status)
      values(c.id,auth.uid(),trim(p_name),phone,'Player','Unverified') returning * into m;
    perform public.audit_event(c.id,null,m.id,'MEMBER_VERIFICATION_REQUESTED',null);
  elsif m.mobile_number<>phone or m.name<>trim(p_name) then
    update public.members set name=trim(p_name),mobile_number=phone,
      verification_code=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),verified_at=null,verified_by=null
      where id=m.id;
    perform public.audit_event(c.id,null,m.id,'MEMBER_VERIFICATION_REQUEST_UPDATED',null);
  end if;
  return public.get_my_membership();
end $$;
revoke all on function public.pilot_join(text,text,text) from public, anon;
grant execute on function public.pilot_join(text,text,text) to authenticated;

create or replace function public.is_admin(p_club_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists(select 1 from public.members where club_id=p_club_id and auth_user_id=auth.uid()
    and role='Admin' and verification_status in ('AdminVerified','OtpVerified'))
$$;
create or replace function public.can_collect(p_match_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists(select 1 from public.matches m join public.members me on me.club_id=m.club_id and me.auth_user_id=auth.uid()
    where m.id=p_match_id and me.verification_status in ('AdminVerified','OtpVerified') and (me.role='Admin' or exists(
      select 1 from public.match_collectors mc where mc.match_id=m.id and mc.member_id=me.id)))
$$;

create or replace function public.approve_member_phone(p_club_id uuid,p_user_id uuid,p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m public.members%rowtype;
begin
  if not public.is_admin(p_club_id) then raise exception 'ADMIN_REQUIRED'; end if;
  select * into m from public.members where club_id=p_club_id and (auth_user_id=p_user_id or id=p_user_id) for update;
  if m.id is null then raise exception 'MEMBER_NOT_FOUND'; end if;
  if m.verification_status<>'Unverified' then raise exception 'ALREADY_VERIFIED'; end if;
  if m.auth_user_id is null then raise exception 'PLAYER_MUST_REQUEST_FROM_THEIR_BROWSER'; end if;
  if p_code is null or upper(trim(p_code))<>m.verification_code then raise exception 'INVALID_VERIFICATION_CODE'; end if;
  update public.members set verification_status='AdminVerified',verified_at=now(),verified_by=public.current_member_id(),
    verification_code=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)) where id=m.id;
  perform public.audit_event(p_club_id,null,m.id,'MEMBER_PHONE_ADMIN_VERIFIED',null);
  return jsonb_build_object('verified',true);
end $$;
revoke all on function public.approve_member_phone(uuid,uuid,text) from public, anon;
grant execute on function public.approve_member_phone(uuid,uuid,text) to authenticated;

create or replace function public.set_member_verified(p_club_id uuid,p_user_id uuid,p_verified boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m public.members%rowtype;
begin
  if not public.is_admin(p_club_id) then raise exception 'ADMIN_REQUIRED'; end if;
  if p_verified is distinct from false then raise exception 'USE_PHONE_VERIFICATION_FLOW'; end if;
  select * into m from public.members where club_id=p_club_id and (auth_user_id=p_user_id or id=p_user_id) for update;
  if m.id is null then raise exception 'MEMBER_NOT_FOUND'; end if;
  if m.role='Admin' then raise exception 'DEMOTE_ADMIN_BEFORE_REMOVING_VERIFICATION'; end if;
  update public.members set verification_status='Unverified',verified_at=null,verified_by=null,
    verification_code=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)) where id=m.id;
  perform public.audit_event(p_club_id,null,m.id,'MEMBER_VERIFICATION_REMOVED',null);
  return jsonb_build_object('verified',false);
end $$;

-- Apply a common verified-membership precondition to every existing business RPC.
-- Keep the reviewed existing bodies, which also enforce the action-specific role/ownership rules.
do $migration$
declare f record; body text;
begin
  for f in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(array[
      'add_walk_in','assign_collector','book_ground','cancel_match','cleanup_old_settled_details','complete_match','create_match',
      'finalize_attendance','get_attendance','get_club_members','get_collection_dashboard','get_collector_options','get_match',
      'get_my_dues','get_pending_payment_claims','get_pending_payment_report','get_reminder_preferences','join_match','leave_match',
      'mark_charge_paid','review_payment_claim','set_member_role','set_reminder_preferences','submit_payment_claim'])
  loop
    body:=pg_get_functiondef(f.oid);
    if position(E'\nbegin\n' in body)=0 then raise exception 'UNEXPECTED_FUNCTION_BODY: %',f.proname; end if;
    body:=replace(body,E'\nbegin\n',E'\nbegin\n  perform private.require_verified_member();\n');
    if f.proname in ('join_match','leave_match') then
      body:=replace(body,'if v_m.id is null or v_me is null then',
        'if not exists(select 1 from public.members where id=v_me and club_id=v_m.club_id) then raise exception ''NOT_CLUB_MEMBER''; end if; if v_m.id is null or v_me is null then');
    end if;
    if f.proname='set_member_role' then
      body:=replace(body,'if v_target.id is null then',
        'if p_role=''Admin'' and v_target.verification_status not in (''AdminVerified'',''OtpVerified'') then raise exception ''MEMBER_VERIFICATION_REQUIRED''; end if; if v_target.id is null then');
    end if;
    execute body;
    execute format('revoke all on function %s from public, anon',f.oid::regprocedure);
    execute format('grant execute on function %s to authenticated',f.oid::regprocedure);
  end loop;
end $migration$;
-- These are internal helpers, not client RPCs.
revoke all on function public.audit_event(uuid,uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function public.maybe_settle(uuid) from public, anon, authenticated;
revoke all on function public.set_member_verified(uuid,uuid,boolean) from public, anon;
grant execute on function public.set_member_verified(uuid,uuid,boolean) to authenticated;
