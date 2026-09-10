# Facial Recognition Kiosk Attendance System

Three pieces sharing one Supabase backend:

- **`kiosk_app/`** — Flutter, Android tablet, kiosk-mode. Live camera
  screen that recognizes enrolled employees on-device and auto-marks
  attendance (check-in on the day's first scan, check-out on the second).
- **`admin_panel/`** — Next.js. The only place with a login. Register
  employees here, capturing several webcam photos per person.
- **`supabase/`** — SQL migrations for the shared Postgres schema, RLS
  policies, and business-logic functions.

**Architecture note:** the admin panel never computes face embeddings — it
only uploads raw photos. The kiosk app is the only thing that ever runs the
face-embedding model, both when enrolling new employees (in the background)
and when recognizing someone live, so there's exactly one model/pipeline in
the whole system and enrollment-time/recognition-time embeddings are always
comparable. See the comment block at the top of
`supabase/migrations/0003_functions.sql` for the full reasoning.

## Setup order

### 1. Create a Supabase project

In the dashboard: **Database → Extensions**, enable `vector`.

### 2. Run the migrations

Open the SQL Editor and run each file in `supabase/migrations/` **in
order** (`0001` → `0005`). If you have the Supabase CLI installed instead,
`supabase db push` works too — there's no `supabase/config.toml` in this
repo yet, so you'll need `supabase link` first.

### 3. Create the admin and kiosk accounts

**Dashboard → Authentication → Add User**, create:

- An admin account, e.g. `admin@yourorg.com` (you'll log into the Next.js
  panel with this).
- A kiosk device account, e.g. `kiosk@yourorg.local` (the Flutter app signs
  in with this once at startup).

Then open `supabase/bootstrap.sql`, fill in both users' UUIDs (from the
Dashboard's user list), and run it in the SQL Editor. This is what actually
grants each account its role (`admin` / `kiosk`) via the `profiles` table —
without it, RLS will block both apps from doing anything.

### 4. Run the admin panel

```sh
cd admin_panel
cp .env.local.example .env.local   # fill in your Supabase project URL + anon key
//npm install
npm run dev
```

Log in with the admin account, then **Employees → Register employee** to
add your first person (capture at least 3 photos — front, left, right).
Their status will show **pending** until the kiosk picks them up.

### 5. Source a face-embedding model for the kiosk

The kiosk needs a `.tflite` face-embedding model (MobileFaceNet or
similar) — this is a binary asset that has to come from you; it can't be
fetched automatically here. Search for **"MobileFaceNet tflite"** or
**"facenet tflite 192d embedding"**. Reference implementations worth
copying the preprocessing conventions from:

- `MCarlomagno/FaceRecognitionAuth`
- `shubham0204/OnDevice-Face-Recognition-Android`

Whatever model you pick, note its **input size** (commonly 112×112) and
**output embedding length**, then update the two constants at the top of
`kiosk_app/lib/services/embedding_service.dart` (`inputSize`,
`embeddingSize`) to match. If `embeddingSize` isn't 192, also update the
`vector(192)` column definition in `supabase/migrations/0001_schema.sql`
(and the `p_embedding::vector(192)` cast in `0003_functions.sql`) to match
before running the migrations.

Place the file at `kiosk_app/assets/models/face_embedding.tflite`.

### 6. Run the kiosk app

The `android/` platform folder doesn't exist yet in this repo — this
environment didn't have the Flutter SDK available to generate it. Follow
`kiosk_app/ANDROID_KIOSK_SETUP.md` first (it walks through `flutter
create`, permissions, and the native lock-task wiring for true
unattended-kiosk behavior).

Then, from `kiosk_app/`:

```sh
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=KIOSK_EMAIL=kiosk@yourorg.local \
  --dart-define=KIOSK_PASSWORD=the-kiosk-account-password
```

Give it a minute after launch: it polls for pending employees every ~45s,
downloads their photos, and runs them through the on-device model. Once an
employee's status flips to **completed** in the admin panel, they're
recognizable — stand in front of the kiosk camera to test check-in, then
again to test check-out, then a third time to see "already completed."

## Things you'll likely need to tune once running on real hardware

None of this could be verified against a real device/camera/Flutter
toolchain while building it — flag these as the first places to look if
something's off:

- **`FaceMatcher.threshold`** (`kiosk_app/lib/services/face_matcher.dart`)
  — cosine-similarity cutoff for accepting a match, starts at 0.65.
- **Camera rotation/mirroring** (`kiosk_app/lib/services/face_image_utils.dart`)
  — YUV→RGB conversion and the rotation applied before cropping are based
  on `camera.sensorOrientation`; this is the most device-manufacturer-
  dependent part of the pipeline.
- **`mark_attendance`'s timezone** (`supabase/migrations/0003_functions.sql`)
  — the check-in/check-out day boundary is hardcoded to `Asia/Kolkata`;
  change it to wherever the kiosk is physically deployed.

## Repo layout

```
kiosk_app/     Flutter kiosk app (Android tablet)
admin_panel/   Next.js admin/registration panel
supabase/      SQL migrations + bootstrap script
```
