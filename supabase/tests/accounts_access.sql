-- Synthetic identities only. All fixtures and decisions roll back; no email is sent.
begin;
select set_config('drivemate.test_owner',gen_random_uuid()::text,true);
select set_config('drivemate.test_driver',gen_random_uuid()::text,true);
select set_config('drivemate.test_admin',gen_random_uuid()::text,true);
insert into auth.users(id,email,aud,role) values
 (current_setting('drivemate.test_owner')::uuid,'owner-'||current_setting('drivemate.test_owner')||'@example.invalid','authenticated','authenticated'),
 (current_setting('drivemate.test_driver')::uuid,'driver-'||current_setting('drivemate.test_driver')||'@example.invalid','authenticated','authenticated'),
 (current_setting('drivemate.test_admin')::uuid,'admin-'||current_setting('drivemate.test_admin')||'@example.invalid','authenticated','authenticated');
insert into private.admin_users(user_id) values(current_setting('drivemate.test_admin')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('drivemate.test_owner'),true);
select public.save_account('Synthetic Owner','owner');
do $$ begin
 if (select count(*) from public.profiles) <> 1 then raise exception 'Own profile missing'; end if;
 begin
  insert into private.admin_users(user_id) values(auth.uid());
  raise exception 'FAIL: self-admin grant allowed';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.subscriptions(user_id,plan_code,status) values(auth.uid(),'fake','active');
  raise exception 'FAIL: fabricated subscription allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('drivemate.test_driver'),true);
select public.save_account('Synthetic Driver','driver');
select public.submit_driver_application(4,'both',true);
do $$ begin
 if (select count(*) from public.profiles) <> 1 then raise exception 'FAIL: cross-account profile exposed'; end if;
 if (select count(*) from public.driver_verifications where status='pending') <> 1 then raise exception 'Pending verification missing'; end if;
 begin
  update public.driver_verifications set status='approved' where driver_id=auth.uid();
  raise exception 'FAIL: direct approval allowed';
 exception when insufficient_privilege then null; end;
 begin
  perform public.review_driver_application(auth.uid(),'rejected',null,false,false,'Synthetic attempted self-review');
  raise exception 'FAIL: self-review allowed';
 exception when raise_exception then
  if sqlerrm <> 'Administrator access required' then raise; end if;
 end;
 begin
  insert into storage.objects(bucket_id,name) values('driver-verification',current_setting('drivemate.test_owner')||'/cross-account.pdf');
  raise exception 'FAIL: cross-account upload allowed';
 exception when insufficient_privilege then null; end;
end $$;
insert into storage.objects(bucket_id,name) values('driver-verification',auth.uid()::text||'/synthetic-licence.pdf');
select public.register_driver_document('licence',auth.uid()::text||'/synthetic-licence.pdf');
select set_config('request.jwt.claim.sub',current_setting('drivemate.test_owner'),true);
do $$ begin
 if exists(select 1 from public.driver_applications) or exists(select 1 from public.driver_documents) or exists(select 1 from storage.objects where bucket_id='driver-verification') then raise exception 'FAIL: driver evidence exposed to owner'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('drivemate.test_admin'),true);
do $$ begin
 if not (public.account_context()->>'is_admin')::boolean then raise exception 'Admin not recognized'; end if;
 if (select count(*) from public.driver_applications) <> 1 then raise exception 'Admin queue missing'; end if;
 begin
  perform public.review_driver_application(current_setting('drivemate.test_driver')::uuid,'approved',current_date+365,true,true,'Synthetic approval gate test');
  raise exception 'FAIL: unverified driver approved';
 exception when raise_exception then
  if sqlerrm <> 'Driver phone verification is required before approval' then raise; end if;
 end;
end $$;
select public.review_driver_application(current_setting('drivemate.test_driver')::uuid,'rejected',null,false,false,'Synthetic rejection to verify audit transaction');
reset role;
do $$ begin
 if (select count(*) from private.verification_events where driver_id=current_setting('drivemate.test_driver')::uuid and event_type='review:rejected')<>1 then raise exception 'Audit event missing'; end if;
 if (select status from public.driver_verifications where driver_id=current_setting('drivemate.test_driver')::uuid)<>'rejected' then raise exception 'Review result missing'; end if;
end $$;
set local role anon;
do $$ begin
 begin
  perform public.account_context();
  raise exception 'FAIL: anonymous account RPC allowed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
select 'PASS' as result,'Account isolation, admin gate, document isolation, approval gate, audit transaction, and anonymous RPC checks. All fixtures rolled back.' as checks;
