-- DriveMate foundation. Apply to a NEW Supabase staging project first.
-- No live fares, payment processing, matching, or subscription sales are enabled.
begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table private.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade
);
create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from private.admin_users where user_id = auth.uid());
$$;
revoke all on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated;

create table public.service_areas (
  code text primary key,
  city text not null,
  state text not null,
  country text not null default 'IN',
  currency text not null default 'INR' check (currency = 'INR'),
  timezone text not null default 'Asia/Kolkata',
  bookings_enabled boolean not null default false
);
insert into public.service_areas(code, city, state)
values ('bengaluru', 'Bengaluru', 'Karnataka');

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 1 and 100),
  service_area text not null default 'bengaluru' references public.service_areas(code),
  created_at timestamptz not null default now()
);
-- Phone verification is derived from auth.users by trusted backend code;
-- it must never be accepted as a client-editable profile flag.
create table public.driver_applications (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  experience_years integer not null check (experience_years between 0 and 70),
  transmission text not null check (transmission in ('manual', 'automatic', 'both')),
  consent_version text not null check (length(trim(consent_version)) > 0),
  consented_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
-- Applicants cannot change evidence after submitting. Resubmission/versioning
-- will be implemented through an audited backend endpoint.
create table public.driver_verifications (
  driver_id uuid primary key references public.driver_applications(user_id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'suspended')),
  licence_expires_on date,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  check (status <> 'approved' or (licence_expires_on is not null and reviewed_by is not null and reviewed_at is not null))
);
-- Reviewer notes/evidence are not exposed to the applicant or the browser API.
create table private.verification_events (
  id bigint generated always as identity primary key,
  driver_id uuid not null references public.driver_applications(user_id),
  actor_id uuid not null references auth.users(id),
  event_type text not null,
  notes text,
  created_at timestamptz not null default now()
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(user_id),
  driver_id uuid references public.driver_applications(user_id),
  service_area text not null default 'bengaluru' references public.service_areas(code),
  pickup_address text not null check (length(trim(pickup_address)) between 5 and 300),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  transmission text not null check (transmission in ('manual', 'automatic')),
  status text not null default 'requested' check (status in ('requested','accepted','arrived','started','completed','cancelled')),
  fare_paise bigint not null check (fare_paise >= 0),
  currency text not null default 'INR' check (currency = 'INR'),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (driver_id is null or driver_id <> owner_id),
  check (status not in ('accepted','arrived','started','completed') or driver_id is not null)
);
create index bookings_owner_start on public.bookings(owner_id, starts_at);
create index bookings_driver_start on public.bookings(driver_id, starts_at);

-- Written only by the future trusted payment/webhook service.
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id),
  provider_payment_id text unique,
  status text not null check (status in ('created','authorized','captured','failed','partially_refunded','refunded')),
  amount_paise bigint not null check (amount_paise >= 0),
  currency text not null default 'INR' check (currency = 'INR'),
  created_at timestamptz not null default now()
);
create index payments_booking on public.payments(booking_id);
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id),
  provider_subscription_id text unique,
  plan_code text not null,
  status text not null check (status in ('pending','active','past_due','cancelled','expired')),
  current_period_end timestamptz,
  created_at timestamptz not null default now()
);
create index subscriptions_user on public.subscriptions(user_id);

alter table public.service_areas enable row level security;
alter table public.profiles enable row level security;
alter table public.driver_applications enable row level security;
alter table public.driver_verifications enable row level security;
alter table public.bookings enable row level security;
alter table public.payments enable row level security;
alter table public.subscriptions enable row level security;
alter table private.admin_users enable row level security;
alter table private.verification_events enable row level security;

revoke all on public.service_areas, public.profiles, public.driver_applications,
  public.driver_verifications, public.bookings, public.payments, public.subscriptions
  from public, anon, authenticated;
grant select on public.service_areas to anon, authenticated;
grant select, insert on public.profiles, public.driver_applications to authenticated;
grant update(full_name) on public.profiles to authenticated;
grant select on public.driver_verifications, public.bookings, public.payments, public.subscriptions to authenticated;
grant all on public.service_areas, public.profiles, public.driver_applications,
  public.driver_verifications, public.bookings, public.payments, public.subscriptions to service_role;

create policy areas_read on public.service_areas for select to anon, authenticated using (true);
create policy profile_read on public.profiles for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
create policy profile_insert on public.profiles for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy profile_update on public.profiles for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy application_read on public.driver_applications for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
create policy application_insert on public.driver_applications for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy verification_read on public.driver_verifications for select to authenticated
  using (driver_id = (select auth.uid()) or (select private.is_admin()));
create policy booking_read on public.bookings for select to authenticated
  using (owner_id = (select auth.uid()) or driver_id = (select auth.uid()) or (select private.is_admin()));
create policy payment_read on public.payments for select to authenticated
  using ((select private.is_admin()) or exists (
    select 1 from public.bookings b where b.id = booking_id and b.owner_id = (select auth.uid())
  ));
create policy subscription_read on public.subscriptions for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

-- Immutable private objects: <auth-user-uuid>/<random-document-uuid>.pdf
-- Server must inspect files before review; MIME declarations are not malware checks.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('driver-verification', 'driver-verification', false, 5242880,
  array['application/pdf','image/jpeg','image/png']);
create policy driver_document_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'driver-verification'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists(select 1 from public.driver_applications where user_id = (select auth.uid())));
create policy driver_document_read on storage.objects for select to authenticated
  using (bucket_id = 'driver-verification'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select private.is_admin())));
-- No client overwrite/delete policies. A trusted retention/deletion service is required.
commit;
