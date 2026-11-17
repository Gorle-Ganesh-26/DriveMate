# DriveMate · Bengaluru backend foundation

Status (18 November 2026): foundation and account migrations applied to Supabase
project wgzvbkujdgwpjdnddjgw. The separate account area uses Supabase email-link
authentication, profiles, driver applications, private sample-document uploads,
and an admin-gated review queue. The landing-page booking form remains a demo.
Live booking and payment writes remain disabled. See ACCOUNT_STATUS.md for the
tested scope and remaining activation steps. Do not rerun the applied migrations.

Launch scope: Bengaluru, Karnataka, India; INR; Asia/Kolkata. Scheduled hourly
drivers first. A city selection does not validate an address: an explicit service
boundary and server-side location checks are required before accepting bookings.

## Next setup

1. Create a Supabase staging project. Choose a region appropriate for the intended
   deployment and data handling requirements. Keep database credentials private.
2. Apply `supabase/migrations/202611170001_foundation.sql` through a trusted SQL
   session. This is a one-time migration inside a transaction.
3. Set up development authentication and create separate owner, driver, and admin
   test accounts. Bootstrap the admin's auth UUID into `private.admin_users` through
   the trusted SQL session, never a self-service client request.
4. Run the acceptance checks below before connecting the UI.
5. Build and connect login, application submission, and admin review screens.
   Driver review writes must go through a server that verifies the admin session.
6. Only after those checks, implement booking/pricing APIs and payment sandbox.

## Hosting and identity decision

The current Sites preview uses platform-managed access; it is not a Supabase user
session. Do not equate these identities or use browser-submitted user IDs as proof
of identity. For the production consumer application, confirm external identity
support on the chosen host first, or deploy the application on a host supporting
Supabase Auth. This migration targets Supabase Auth; it does not silently replace
Sites authentication. The preview remains private.

## Configuration names (no credentials in source)

The future app needs SUPABASE_URL and a Supabase publishable key. A trusted
server also needs a Supabase secret key, configured as a runtime secret only.
Do not paste secret keys into chat or put them under `dist/`. Service-role access
bypasses row policies: every server handler must authenticate, authorize, validate,
and rate-limit the operation before using it. Keep local .env files untracked.

## Security and functional acceptance checks

- Anonymous users can read service-area configuration, but not profiles,
  applications, documents, bookings, payments, or subscriptions.
- Owner A can create/read their profile and change their name, but cannot read
  Owner B's profile or change their own user ID, city, or creation time.
- A driver can submit their own application, but cannot approve themselves,
  edit a submitted application, or read another driver's evidence.
- An admin can read the review queue; a non-admin cannot grant themselves admin.
- A document upload to another user's UUID folder is denied. A private object
  cannot be downloaded anonymously. Overwriting an uploaded file is denied.
- Clients cannot insert or change fares, driver assignments, payments,
  subscription entitlements, or booking status directly.
- Admin approval endpoint must validate phone verification, identity/licence
  evidence, expiry, consent, and reviewer identity, then write an audit event in
  the same transaction. An uploaded file alone never establishes verification.

## Remaining backend implementation

- Session-aware endpoints; email login for development, phone OTP integration
  before pilot; MFA for admins; abuse controls and SMS rate limits.
- Document registry with evidence versions, malware/type inspection, review
  workflow, explicit consent text/version, re-verification and expiry handling.
- Booking APIs with server-calculated quotes, quote expiry, idempotency keys,
  future-time/service-area validation, approved-driver checks, and transactional
  overlap prevention (including concurrent acceptance). Current SQL deliberately
  grants no client booking writes and leaves bookings_enabled=false.
- Driver availability, vehicles, notifications, trip PIN verification, incident
  handling, cancellation/refund policy, and audited trip state transitions.
- Payment sandbox, verified/idempotent webhooks, a financial ledger, payouts and
  reconciliation. Subscription table is a placeholder; no plan is for sale.
- Document/database retention, account deletion, access logging, monitored backups,
  storage backup/restore, and restore drills before using real customer data.
- Local operating/insurance/privacy review before the Bengaluru pilot.

## Validation record

Both SQL migrations were executed successfully through the authenticated Supabase
SQL Editor. supabase/tests/accounts_access.sql passed on the project using
transaction-scoped synthetic identities; all test fixtures were rolled back.
Browser account registration/sign-in screens were checked at desktop and mobile
sizes. Human email delivery and end-to-end login remain to be tested by the owner.
Booking concurrency is not implemented or tested; live bookings remain disabled.

References:
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/storage/security/access-control
- https://supabase.com/docs/guides/database/functions
