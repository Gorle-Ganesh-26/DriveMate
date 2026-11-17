# DriveMate accounts · 18 November 2026

## Implemented

- `/account.html`: Supabase email-link sign-up/sign-in, optional emailed code,
  sign-out, account profile, owner booking history, driver application, and private
  sample-document uploads. The SDK is vendored from the pinned npm release
  @supabase/supabase-js 2.119.0 via jsDelivr (MIT).
- Current Sites access gate remains private and unchanged. This is an additional
  application account; a Sites identity is never treated as a Supabase identity.
  The portable static account UI can also be deployed on a consumer host later.
- Admin menu is server-derived through `account_context`; no client metadata can
  grant admin rights. Review RPC verifies admin membership, validates decisions,
  locks the verification record, and records the decision plus audit in one
  transaction. Approved status requires phone confirmation, three registered
  evidence files, manual identity/licence checks, and a current licence expiry.
- Private signed document links expire after 60 seconds. This pilot accepts sample
  files only; MIME/size restrictions do not constitute malware scanning.
- Supabase default Site URL configured to the exact private DriveMate account URL.
  Browser configuration contains only the URL and publishable key, no secret key.

## Verified

- Account migration applied successfully to wgzvbkujdgwpjdnddjgw.
- Live SQL tests passed: own-profile access, cross-account profile/document
  isolation, self-admin grant denial, fabricated subscription denial, direct
  verification update denial, non-admin review denial, cross-account upload
  denial, pending verification creation, document registration, admin queue access,
  unverified-phone approval denial, audit transaction, anonymous account RPC denial.
  All synthetic users, storage metadata, and decisions rolled back.
- JS syntax checks passed. Local account pages loaded with no console warnings or
  errors. Mobile view was inspected at 390px with no horizontal overflow.

## Owner activation

1. Open the deployed `/account.html`, choose Create account, enter your own email,
   and open its sign-up link. Email is sent only when you submit the form. Supabase
   development email limits/restrictions apply; configure custom SMTP for pilots
   with invited users outside the Supabase organisation.
2. Complete a profile. For testing, submit a driver application with sample files.
   Do not upload real identity evidence yet.
3. Explicitly designate the signed-in account that should receive admin access.
   A trusted administrator must add its auth UUID to private.admin_users. No real
   user has been granted admin access by this implementation.
4. Test actual email delivery, sign-in callback, persistence, sign-out, and the
   review screens with separate real test accounts before inviting anyone.

## Before a real pilot

Phone OTP/provider, admin MFA, production SMTP and abuse protections, document
scanning, privacy/retention/deletion workflow, support/incident operations, and a
review of verification decisions remain necessary. Approval checks record a
reviewer's attestations; they do not independently query a licence authority.
Evidence correction/resubmission, expired-document handling, queue pagination,
upload orphan cleanup, and audited admin management are follow-up work.
Bookings, driver matching, trip lifecycle, payments and subscriptions are not
activated. No pricing or membership benefit is promised by this account release.
