-- Run inside BEGIN/ROLLBACK after the migration. Fixtures never persist.
do $test$
declare
  club uuid:=gen_random_uuid(); other_club uuid:=gen_random_uuid(); admin_user uuid:=gen_random_uuid();
  player_user uuid:=gen_random_uuid(); attacker_user uuid:=gen_random_uuid(); admin_member uuid:=gen_random_uuid();
  match_id uuid:=gen_random_uuid(); other_match uuid:=gen_random_uuid(); player_member uuid; code text; old_code text; r jsonb; errored boolean;
  invite text:='test-'||gen_random_uuid()::text;
begin
  insert into auth.users(id,aud,role,is_anonymous) values(admin_user,'authenticated','authenticated',true),(player_user,'authenticated','authenticated',true),(attacker_user,'authenticated','authenticated',true);
  insert into public.clubs(id,name) values(club,'Verification test'),(other_club,'Other verification test');
  insert into public.club_invites(club_id,code) values(club,invite);
  insert into public.members(id,club_id,auth_user_id,name,mobile_number,role,verification_status)
    values(admin_member,club,admin_user,'Test Admin','+919000000001','Admin','AdminVerified');
  insert into public.matches(id,club_id,created_by,match_date,start_time,end_time)
    values(match_id,club,admin_member,current_date+2,'07:00','08:00'),(other_match,other_club,admin_member,current_date+3,'07:00','08:00');
  perform set_config('request.jwt.claim.sub',player_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',player_user,'role','authenticated')::text,true);
  set local role authenticated;
  -- Invalid formats are rejected by the server, even if the UI is bypassed.
  errored:=false;
  begin perform public.pilot_join(invite,'Player','abc9876543210'); exception when others then
    if sqlerrm<>'INVALID_MOBILE' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL invalid phone accepted'; end if;
  r:=public.pilot_join(invite,'Player','+971501234567');
  if r->>'verificationStatus'<>'Unverified' or length(r->>'verificationCode')<>8 then raise exception 'FAIL request not pending'; end if;
  code:=r->>'verificationCode';
  -- A random but well-formed number grants no club access.
  errored:=false;
  begin perform public.join_match(match_id); exception when others then
    if sqlerrm<>'MEMBER_VERIFICATION_REQUIRED' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL pending member joined'; end if;
  errored:=false;
  begin perform public.get_match(match_id); exception when others then
    if sqlerrm<>'MEMBER_VERIFICATION_REQUIRED' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL pending member read match'; end if;
  errored:=false;
  begin perform public.create_match(club,current_date+5,'07:00','08:00',50,14,null,null); exception when others then
    if sqlerrm<>'MEMBER_VERIFICATION_REQUIRED' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL pending member created match'; end if;
  errored:=false;
  begin perform public.approve_member_phone(club,player_user,code); exception when others then
    if sqlerrm<>'ADMIN_REQUIRED' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL self approval'; end if;
  -- Direct table writes cannot bypass RPC approval.
  begin
    update public.members set verification_status='AdminVerified' where auth_user_id=player_user;
    if found then raise exception 'FAIL direct member update'; end if;
  exception when insufficient_privilege then null; end;
  if public.get_my_membership()->>'verificationStatus'<>'Unverified' then raise exception 'FAIL approval bypass'; end if;
  -- Correcting the number rotates the request code.
  old_code:=code;
  r:=public.pilot_join(invite,'Player corrected','+966501234567'); code:=r->>'verificationCode';
  if code=old_code or r->>'mobileNumber'<>'+966501234567' then raise exception 'FAIL correction'; end if;
  reset role;
  select id into player_member from public.members where auth_user_id=player_user;
  perform set_config('request.jwt.claim.sub',attacker_user::text,true);
  set local role authenticated;
  errored:=false;
  begin perform public.pilot_join(invite,'Duplicate','+966501234567'); exception when others then
    if sqlerrm<>'PHONE_ALREADY_REGISTERED' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL duplicate phone'; end if;
  reset role;
  perform set_config('request.jwt.claim.sub',admin_user::text,true);
  set local role authenticated;
  errored:=false;
  begin perform public.set_member_verified(club,player_user,true); exception when others then
    if sqlerrm<>'USE_PHONE_VERIFICATION_FLOW' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL old approval shortcut'; end if;
  errored:=false;
  begin perform public.set_member_role(club,player_user,'Admin'); exception when others then
    if sqlerrm<>'MEMBER_VERIFICATION_REQUIRED' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL pending admin promotion'; end if;
  errored:=false;
  begin perform public.approve_member_phone(club,player_user,old_code); exception when others then
    if sqlerrm<>'INVALID_VERIFICATION_CODE' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL stale code'; end if;
  perform public.approve_member_phone(club,player_user,code);
  errored:=false;
  begin perform public.approve_member_phone(club,player_user,code); exception when others then
    if sqlerrm<>'ALREADY_VERIFIED' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL reused approval'; end if;
  reset role;
  perform set_config('request.jwt.claim.sub',player_user::text,true);
  set local role authenticated;
  perform public.join_match(match_id);
  perform public.get_match(match_id);
  errored:=false;
  begin perform public.join_match(other_match); exception when others then
    if sqlerrm<>'NOT_CLUB_MEMBER' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL cross-club join'; end if;
  reset role;
  perform set_config('request.jwt.claim.sub',admin_user::text,true);
  set local role authenticated;
  errored:=false;
  begin perform public.set_member_verified(club,admin_user,false); exception when others then
    if sqlerrm<>'DEMOTE_ADMIN_BEFORE_REMOVING_VERIFICATION' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL admin lockout'; end if;
  perform public.set_member_verified(club,player_user,false);
  reset role;
  perform set_config('request.jwt.claim.sub',player_user::text,true);
  set local role authenticated;
  errored:=false;
  begin perform public.join_match(match_id); exception when others then
    if sqlerrm<>'MEMBER_VERIFICATION_REQUIRED' then raise; end if; errored:=true; end;
  if not errored then raise exception 'FAIL revocation'; end if;
  reset role;
end $test$;
select 'PASS: signup, approval, bypass prevention, code rotation, revocation and club isolation' as verification_tests;
