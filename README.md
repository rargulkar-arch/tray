# Tray

See which friends are eating, without asking anyone.

You walk into a dining hall; Tray notices and puts your name on a list. Your
friends open the app and see who is where. That is the entire product.

It deliberately is not Find My or Life360. Your friends never see your location
— only which dining hall you are in and how long you have been there, and only
while you are there. Walk out and you disappear. The sharing is small enough
that handing it to someone you met last week costs nothing.

> **Picking this up from someone else?** Read [HANDOFF.md](HANDOFF.md) first —
> it says what is tested, what has never been compiled, and which parts look
> simplifiable but are not.

## What it does

- **Automatic check-in.** Geofences around every dining hall. iOS wakes the app
  when you arrive, even when it is closed. Nothing to open, nothing to tap.
- **Who's eating.** Friends grouped by hall, each with how long they have been
  sitting there.
- **Ask someone to join.** One tap on a friend sends "Rohit is asking you to
  join them at The Eatery." They answer with one of four buttons: *On my way*,
  *In a bit*, *Already ate*, *Can't*.
- **Arrival alerts, off by default.** Per friend. Tray never pings you just
  because somebody walked into a hall — only when you asked about that specific
  person, or when someone asks you to come eat.
- **Invisible today.** Hides you from everyone until midnight. Friends are not
  told, and cannot tell invisible apart from not eating.
- **Groups.** Private labels — "lab group", "floor 12" — to filter the list.
  Nobody is told which groups they are in.
- **Hall busyness.** Anonymous counts across everyone on Tray, bucketed so a
  number never identifies anybody in a half-empty hall.

## How it is built

```
supabase/migrations/   Postgres schema, row level security, and every RPC
supabase/seed.sql      Northeastern's dining halls, with real coordinates
ios/project.yml        XcodeGen project definition
ios/Tray/              The app
```

The phone talks to Postgres and nothing else. Every rule about who can see what
is a row level security policy or a `security definer` function, so the app
cannot leak something by forgetting a filter — the database will not send it.
The privacy model is essentially one policy, `checkins_read` in
`0002_security.sql`: you can see a check-in if it is yours, or if you are
friends and they are not invisible.

There are no third-party Swift packages. `Services/Backend.swift` is a
hand-written Supabase client in about 260 lines: phone auth, token refresh, and
RPC. That is less code than debugging an SDK version mismatch.

### Two things that are harder than they look

**Overlapping geofences.** Stetson East and Stetson West are about 50 metres
apart. A single step can be inside both circles, and iOS will fire both. So an
entry event is treated as a hint: the app takes a fresh fix and checks you into
whichever hall is actually nearest. Exits do the same, because leaving Stetson
East often just means walking into Stetson West.

**Exits are not guaranteed.** iOS does not promise a region exit event. Tray
re-checks its regions at every launch and on significant location changes, and
the database expires a forgotten check-in after three hours, so nobody is left
"eating" overnight.

## Setup

### 1. Supabase

Make a free project at [supabase.com](https://supabase.com). In the SQL editor,
run these in order:

```
supabase/migrations/0001_init.sql
supabase/migrations/0002_security.sql
supabase/migrations/0003_rpc.sql
supabase/migrations/0004_social.sql
supabase/migrations/0005_labels.sql
supabase/migrations/0006_grants.sql
supabase/seed.sql
```

`seed.sql` is safe to re-run; it updates coordinates in place.

### 2. Phone sign-in without paying for texts

Authentication → Sign In / Providers → **Phone**: turn it on. Scroll to **Test
phone numbers** and add a pair, for example `+15550001111` → `123456`. Those
numbers sign in with that fixed code and no SMS is sent, so you can test the
whole app for free. Add a Twilio account later and real numbers start working
with no code change.

### 3. The app

```bash
cd ios
cp Tray/Resources/Secrets.example.xcconfig Tray/Resources/Secrets.xcconfig
```

Put your project's values in `Secrets.xcconfig` — Settings → API in Supabase.
The host goes in **without** `https://`, because `//` starts a comment in an
xcconfig file:

```
SUPABASE_HOST = abcdefgh.supabase.co
SUPABASE_ANON_KEY = eyJhbGciOi...
```

Then:

```bash
brew install xcodegen
cd ios && xcodegen generate && open Tray.xcodeproj
```

### 4. Running it

In the Simulator, Features → Location → Custom Location, and enter a hall's
coordinates from `seed.sql` to trigger a check-in. The **I'm here** button on the
Now screen checks in by hand, which is the faster way to exercise the rest of
the app.

On your own iPhone, Xcode's free provisioning will sign and install it — Signing
& Capabilities, pick your personal team, change the bundle identifier to
something unique. The build expires after seven days and you reinstall it.

## What a paid Apple developer account unlocks

Everything above works for $0. The $99/year account adds three things, none of
which is a rewrite:

| | Without | With |
|---|---|---|
| Friends' phones | Only yours, 7-day builds | TestFlight |
| Invite notifications | While the app runs or during an iOS background refresh window | Instant push |
| Sign in with Apple | Not available (it is a paid entitlement) | One-tap signup |

The `device_tokens` table and the `alerts_since` function already exist for
push; turning it on means an edge function calling the same query and sending to
APNs, rather than the phone polling it.

## What has been verified

The backend has been run. The migrations and seed were applied to a real
Postgres 16 instance and exercised end to end: mutual friendship including two
people adding each other at once, idempotent re-entry to the same hall, moving
between halls, invisible mode hiding you mid-meal, invite de-duplication,
invites refused when you are not at a hall, arrival alerts firing only for
friends you subscribed to, private groups, bucketed busyness, and unfriending
cutting visibility both ways. The row level security policies were tested
directly as the `authenticated` role: a stranger reading the `checkins` table
gets zero rows, a forged check-in is rejected, and `anon` cannot call the RPCs.

The iOS app has **not been compiled** — this machine has Xcode's command line
tools but not Xcode itself, so there is no iOS SDK to build against. Every
source file parses, and the project generates, but expect to fix some compile
errors on the first build.

## Known limits

- **Notifications are best-effort until push exists.** iOS decides when to grant
  background refresh windows, and it is not generous. An invite can arrive late.
- **Busyness reads low** until a real number of people are using Tray, because
  it counts Tray users rather than the whole hall. Northeastern does not publish
  a live capacity feed; Google's Popular Times has no public API.
- **The share link** (`https://tray.app/add/<username>`) needs a real domain and
  an `apple-app-site-association` file before it opens the app. Today it carries
  a username someone can paste into search.
- **Northeastern only.** The schema is multi-campus, but only one campus is
  seeded, and the signup flow hardcodes `neu`.
