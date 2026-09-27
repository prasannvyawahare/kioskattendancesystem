# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo layout

Three independent projects sharing one Supabase backend (no root package.json / monorepo tooling — `cd` into each):

- **`kiosk_app/`** — Flutter, Android tablet, kiosk-mode. Live camera screen that recognizes enrolled
  members on-device and auto-marks attendance (check-in on the day's first scan, check-out on the
  second), plus a PIN-gated on-device enrollment flow.
- **`admin_panel/`** — Next.js 14 (App Router). The only place with a login. Register members here
  (webcam photos) and manage kiosk-wide settings (greetings, voice, enrollment toggle).
- **`supabase/`** — SQL migrations for the shared Postgres schema, RLS policies, and business-logic
  functions.

**Core architectural invariant:** the admin panel never computes face embeddings — it only uploads
raw photos. The kiosk app is the *only* thing that ever runs the face-embedding model, both when
enrolling members (background sync of admin-captured photos, or on-device enrollment) and when
recognizing someone live, so there is exactly one model/pipeline in the whole system and
enrollment-time/recognition-time embeddings are always comparable. See the comment block at the top
of `supabase/migrations/0003_functions.sql`.

**Write pattern:** the kiosk never gets broad table INSERT/UPDATE grants. All of its writes go
through `SECURITY DEFINER` Postgres RPCs (`mark_attendance`, `record_face_embedding`,
`mark_embedding_failed`, `enroll_member`, `record_member_photo`, `verify_enrollment_pin`) that check
`profiles.role = 'kiosk'` internally — see `supabase/migrations/0003_functions.sql` and
`0007_kiosk_enrollment.sql`.

## Commands

### kiosk_app (Flutter)

```sh
cd kiosk_app
flutter pub get
flutter analyze

flutter run \
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=KIOSK_EMAIL=kiosk@yourorg.local \
  --dart-define=KIOSK_PASSWORD=the-kiosk-account-password \
  --dart-define=ENABLE_ENROLLMENT=true   # optional, see Config below
```

Same `--dart-define` flags apply to `flutter build apk`. There is no `test/` suite in this project
yet (`flutter test` is wired up via the `flutter_test` dev dependency but no tests exist).

The `android/` platform folder is checked in with kiosk-mode (Device Owner + lock task) already
wired — see `kiosk_app/ANDROID_KIOSK_SETUP.md` for what's required on the physical tablet side
(factory reset, `adb shell dpm set-device-owner ...`) before lock task is actually unbreakable.

### admin_panel (Next.js)

```sh
cd admin_panel
npm install
cp .env.local.example .env.local   # fill in Supabase project URL + anon key
npm run dev      # http://localhost:3000
npm run build
npm run lint
```

No test script is defined in `package.json`.

### supabase

No `supabase/config.toml` — either paste each file in `supabase/migrations/` into the dashboard's
SQL Editor **in order** (`0001` → `0007`), or `supabase link` first and run `supabase db push`.
After migrating, run `supabase/bootstrap.sql` (with real admin/kiosk auth user UUIDs substituted in)
to grant those two accounts their `profiles.role`. Enable the `vector` extension in
**Database → Extensions** before running `0001_schema.sql`.

## Architecture

### End-to-end flow

1. **Enroll** — either in `admin_panel` (webcam capture → raw photos in Storage,
   `employees.embedding_status = 'pending'`), or directly on the kiosk via the PIN-gated flow
   (`PinEntryScreen` → `MemberListScreen` → `AddMemberScreen`), which embeds locally and skips the
   pending/poll step.
2. **Embed** (admin-panel path only) — `EnrollmentSyncService` on the kiosk polls every 45s for
   pending members, downloads their photos, runs ML Kit face detect + crop + the on-device model,
   and writes embeddings via `record_face_embedding()`.
3. **Recognize** — `CameraScreen` streams camera frames, requires a few stable single-face
   detections, crops/embeds, and does in-memory cosine-similarity matching (`FaceMatcher`) against
   members refreshed periodically from Supabase.
4. **Mark attendance** — `mark_attendance()` (Postgres RPC) atomically decides
   check-in/check-out/already-completed per day, advisory-locked per employee, with a hardcoded
   `Asia/Kolkata` day boundary (change this if kiosks are deployed elsewhere).
5. **Greet** — on check-in/check-out, `GreetingService` renders the admin-configured template
   (`kiosk_settings.checkin_greeting_template` / `checkout_greeting_template`, placeholders `{name}`,
   `{time_greeting}`, `{institution}`) and speaks it via `flutter_tts`.
6. **Notify parents** — an `attendance_logs` INSERT fires a `pg_net`-backed Postgres trigger
   (`migrations/0022_attendance_whatsapp_webhook_trigger.sql`) into the `send-attendance-whatsapp`
   Edge Function, which messages `employees.mother_phone`/`father_phone` via Twilio over whichever
   channel `kiosk_settings.parent_notification_channel` (`disabled` / `whatsapp` / `sms`) picks. This
   is the admin-panel path only in the sense that the channel picker lives in Settings — the send
   itself runs entirely in the Edge Function regardless of whether anyone has the dashboard open,
   since it's triggered off the same `attendance_logs` table `mark_attendance()` writes to.

### Key files (kiosk_app)

- `lib/screens/camera_screen.dart` — the app's home/idle screen: live preview, face detection,
  matching, attendance marking, the bottom-panel result UI, and the hidden long-press gesture
  (top-left corner) into the PIN-gated enrollment flow. Owns the single `CameraController`, which it
  releases before pushing enrollment screens (only one controller can hold the camera at a time) and
  re-acquires on return.
- `lib/services/embedding_service.dart` — the only place the `.tflite` model
  (`assets/models/face_embedding.tflite`, FaceNet 160×160 → 512-d) runs. Shared as a single loaded
  instance across `CameraScreen`, `EnrollmentSyncService`, and `AddMemberScreen` — never load a second
  instance, it's ~93MB.
- `lib/services/face_image_utils.dart` — Android-only YUV→RGB conversion, sensor rotation, and
  cropping. The most device-manufacturer-dependent code in the app; unverified against real hardware.
- `lib/services/face_matcher.dart` — cosine-similarity threshold (`0.65` default) needs tuning
  against real false-accept/false-reject rates once running on-device.
- `lib/services/kiosk_settings_service.dart` — caches the admin-managed `kiosk_settings` singleton
  row; `enrollmentAllowed` ANDs the `ENABLE_ENROLLMENT` build flag with the row's
  `enrollment_enabled` toggle, so enrollment needs both the kiosk built for it *and* the admin
  leaving it on.
- `lib/config.dart` — all secrets/flags come in via `--dart-define`, nothing sensitive in source.

### Key files (supabase)

- `migrations/0001_schema.sql` / `0002_rls.sql` — core tables (`profiles`, `employees`,
  `employee_photos`, `face_embeddings` (`vector(512)`), `attendance_logs`) and their RLS: admins get
  full CRUD, kiosks get narrow read access plus the RPCs below.
- `migrations/0003_functions.sql` — `mark_attendance()`, `record_face_embedding()`,
  `mark_embedding_failed()`.
- `migrations/0006_embedding_dim_512.sql` — records why the embedding column is `vector(512)`
  (standard FaceNet) rather than the originally planned `vector(192)` (MobileFaceNet).
- `migrations/0007_kiosk_enrollment.sql` — the `kiosk_settings` singleton table, PIN-lockout columns
  on `profiles`, and `verify_enrollment_pin()` / `enroll_member()` / `record_member_photo()` /
  `set_enrollment_pin()`. PINs are hashed with pgcrypto (`crypt()`/`gen_salt('bf')`) and never stored
  or transmitted as plaintext outside a single RPC call.
- `migrations/0016_parent_contacts.sql` — `mother_phone`/`father_phone` etc. on `employees`, the data
  that `functions/send-attendance-whatsapp` sends to.
- `migrations/0021_whatsapp_notifications.sql` / `0023_notification_channel.sql` — the
  `attendance_notification_log` delivery log, and `kiosk_settings.parent_notification_channel`
  (`disabled` / `whatsapp` / `sms`; 0023 replaced 0021's original WhatsApp-only boolean toggle).
- `migrations/0022_attendance_whatsapp_webhook_trigger.sql` — the `pg_net` trigger on
  `attendance_logs` INSERT that calls the Edge Function below, with the shared secret it
  authenticates with embedded in the trigger body (must match the function's
  `ATTENDANCE_WEBHOOK_SECRET` secret — see that migration's header comment if it's ever rotated).
- `functions/send-attendance-whatsapp/` — Edge Function invoked by the above trigger; sends the
  Twilio WhatsApp/SMS message depending on the selected channel. WhatsApp needs an approved Content
  Template (`TWILIO_CONTENT_SID`) since attendance pings are always business-initiated; SMS to Indian
  numbers needs DLT template registration; both need a non-trial Twilio account for real (non-
  Sandbox, non-verified-number) recipients. Twilio credentials live only in Edge Function secrets
  (`supabase secrets set`), never in `kiosk_app`/`admin_panel` env files — see the README in that
  folder for full setup.

### Key files (admin_panel)

- `src/lib/database.types.ts` — hand-written types mirroring the SQL schema (no
  `supabase gen types` in use); update this whenever a migration changes the schema.
- `src/app/(dashboard)/employees/actions.ts` — server actions for registering members and uploading
  enrollment photos to the `employee-photos` Storage bucket.
- `src/app/(dashboard)/settings/` — admin-managed kiosk config (institution name, member label,
  greeting templates, voice/enrollment toggles, PIN rotation via `set_enrollment_pin()`); changes
  reach running kiosks within about a minute via `KioskSettingsService`'s poll.
- `src/app/(dashboard)/dashboard/live-attendance-feed.tsx` — Supabase Realtime subscription on
  `attendance_logs` INSERTs.

## Things known to need tuning on real hardware

None of the camera/model/TTS pipeline has been verified against real hardware. First places to
check if something's off:

- `FaceMatcher.threshold` (`kiosk_app/lib/services/face_matcher.dart`)
- Camera rotation/mirroring (`kiosk_app/lib/services/face_image_utils.dart`)
- `mark_attendance()`'s hardcoded `Asia/Kolkata` timezone (`supabase/migrations/0003_functions.sql`)
- `flutter_tts` voice/locale behavior and offline language-pack availability on the target tablet
- The camera-release/re-acquire handoff around enrollment screens
  (`CameraScreen._stopCamera`/`_startCamera` in `camera_screen.dart`)
