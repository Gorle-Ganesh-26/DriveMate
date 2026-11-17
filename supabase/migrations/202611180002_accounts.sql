begin;
alter table public.profiles add column account_kind text not null default 'owner' check(account_kind in ('owner','driver'));
create table public.driver_documents (
 id uuid primary key default gen_random_uuid(),
 driver_id uuid not null references public.driver_applications(user_id),
 kind text not null check(kind in ('licence','identity','portrait')),
 object_path text not null unique,
 created_at timestamptz not null default now(),
 unique(driver_id,kind)
);
alter table public.driver_documents enable row level security;
revoke all on public.driver_documents from public,anon,authenticated;
grant select on public.driver_documents to authenticated;
grant all on public.driver_documents to service_role;
create policy documents_read on public.driver_documents for select to authenticated
 using(driver_id=(select auth.uid()) or (select private.is_admin()));
revoke insert on public.profiles,public.driver_applications from authenticated;

-- SECURITY DEFINER is limited to these checked operations; no caller-supplied user IDs.
create function public.account_context() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('is_admin',private.is_admin(),'phone_verified',exists(select 1 from auth.users where id=auth.uid() and phone_confirmed_at is not null));
$$;
create function public.save_account(p_name text,p_kind text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if p_kind is null or p_kind not in ('owner','driver') or p_name is null or length(trim(p_name)) not between 1 and 100 then raise exception 'Invalid profile'; end if;
 insert into public.profiles(user_id,full_name,account_kind) values(auth.uid(),trim(p_name),p_kind)
 on conflict(user_id) do update set full_name=excluded.full_name;
end; $$;
create function public.submit_driver_application(p_experience integer,p_transmission text,p_consent boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if p_consent is distinct from true then raise exception 'Consent is required'; end if;
 if p_experience is null or p_experience not between 0 and 70 or p_transmission is null or p_transmission not in ('manual','automatic','both') then raise exception 'Invalid application'; end if;
 insert into public.driver_applications(user_id,experience_years,transmission,consent_version)
 values(auth.uid(),p_experience,p_transmission,'pilot-verification-v1');
 insert into public.driver_verifications(driver_id) values(auth.uid());
 update public.profiles set account_kind='driver' where user_id=auth.uid();
end; $$;
create function public.register_driver_document(p_kind text,p_path text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or split_part(p_path,'/',1) is distinct from auth.uid()::text then raise exception 'Not your document'; end if;
 if p_kind is null or p_kind not in ('licence','identity','portrait') then raise exception 'Invalid document type'; end if;
 if not exists(select 1 from public.driver_verifications where driver_id=auth.uid() and status='pending') then raise exception 'Application is not pending'; end if;
 if not exists(select 1 from storage.objects where bucket_id='driver-verification' and name=p_path) then raise exception 'Upload the file first'; end if;
 insert into public.driver_documents(driver_id,kind,object_path) values(auth.uid(),p_kind,p_path);
end; $$;
create function public.review_driver_application(p_driver uuid,p_status text,p_expiry date,p_identity_checked boolean,p_licence_checked boolean,p_note text) returns void language plpgsql security definer set search_path='' as $$
declare v_old text;
begin
 if auth.uid() is null or not private.is_admin() then raise exception 'Administrator access required'; end if;
 if p_status is null or p_status not in ('approved','rejected','suspended') then raise exception 'Invalid review status'; end if;
 if p_note is null or length(trim(p_note)) not between 5 and 2000 then raise exception 'Provide a review note (5–2000 characters)'; end if;
 select status into v_old from public.driver_verifications where driver_id=p_driver for update;
 if not found then raise exception 'Application not found'; end if;
 if v_old=p_status then raise exception 'This status is already recorded'; end if;
 if p_status='approved' then
  if p_expiry is null or p_expiry < (now() at time zone 'Asia/Kolkata')::date then raise exception 'A current licence expiry is required'; end if;
  if p_identity_checked is distinct from true or p_licence_checked is distinct from true then raise exception 'Complete identity and licence checks'; end if;
  if not exists(select 1 from auth.users where id=p_driver and phone_confirmed_at is not null) then raise exception 'Driver phone verification is required before approval'; end if;
  if (select count(distinct kind) from public.driver_documents where driver_id=p_driver and kind in ('licence','identity','portrait'))<>3 then raise exception 'All three verification documents are required'; end if;
 end if;
 update public.driver_verifications set status=p_status,licence_expires_on=case when p_status='approved' then p_expiry else licence_expires_on end, reviewed_by=auth.uid(),reviewed_at=now() where driver_id=p_driver;
 insert into private.verification_events(driver_id,actor_id,event_type,notes) values(p_driver,auth.uid(),'review:'||p_status,trim(p_note));
end; $$;
revoke all on function public.account_context(),public.save_account(text,text),public.submit_driver_application(integer,text,boolean),public.register_driver_document(text,text),public.review_driver_application(uuid,text,date,boolean,boolean,text) from public,anon;
grant execute on function public.account_context(),public.save_account(text,text),public.submit_driver_application(integer,text,boolean),public.register_driver_document(text,text),public.review_driver_application(uuid,text,date,boolean,boolean,text) to authenticated;
commit;
