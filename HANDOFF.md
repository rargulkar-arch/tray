# Handoff

Read this before anything else. It says what is real, what is untested, and
where the landmines are. `README.md` covers setup; this covers judgement.

## What Tray is

College students eat in dining halls and want to eat with friends, but
coordinating it means texting a group and collecting a mix of "already ate",
"going later" and silence. Tray removes the asking: walk into a dining hall,
get added to a list automatically, and your friends can see where you are.

The design constraint that matters: **it shares presence, not location.** A
friend sees *which hall* and *how long you have been there* — nothing else, and
only while you are there. Walk out and you vanish. That is deliberately less
than Find My or Life360, because the point is that it should cost nothing to
share with someone you met last week.

Do not let this drift into a location app. If a feature needs a map, it is
probably the wrong feature.

## What is in the box

| Piece | What it is | State |
|---|---|---|
| `prototype/index.html` | Every screen, clickable, fake data, no backend. One file, vanilla JS. | **Works.** [Live here](https://rargulkar-arch.github.io/tray/). |
| `supabase/migrations/` | Postgres schema, row level security, and every RPC the app calls. | **Tested.** See below. |
| `supabase/seed.sql` | Northeastern's five dining halls with real coordinates. | **Tested**, idempotent. |
| `ios/Tray/` | The SwiftUI app. ~2,000 lines across 20 files. | **Never compiled.** See below. |

## What has actually been verified

**The backend has been run.** All six migrations and the seed were applied to a
real Postgres 16 instance and exercised end to end: mutual friendship including
the case where two people add each other simultaneously, idempotent re-entry to
the same hall, moving between halls, invisible mode hiding someone mid-meal,
invite de-duplication, invites refused when the sender is not at a hall,
arrival alerts firing only for subscribed friends, private groups, bucketed
busyness, and unfriending cutting visibility both ways.

The RLS policies were then tested directly as the `authenticated` role, not
just through the `security definer` functions: a stranger reading the
`checkins` table gets zero rows, a forged check-in is rejected by the policy,
and `anon` cannot execute the RPCs. No policy recursion.

**The iOS app has never been compiled.** The machine it was written on has
Xcode's command line tools but not Xcode, so there is no iOS SDK to build
against. Every file parses and the XcodeGen project generates, and a static
review already caught five real defects (a main-actor violation in the
background task handler, an error match that would not compile, a `nil` that
would crash JSON encoding, a nested-observable bug that would have frozen the
permission banner on screen, and a double slash in every URL). Expect more on
first build. Budget half a day.

## Pick a direction

Nothing commits you to the iOS app. Three honest options:

**1. Finish the iOS app.** The backend is done and tested, so this is mostly
compile-and-fix plus device testing. You get real background geofencing, which
is the entire product. Needs a Mac, Xcode, and — for anything beyond your own
phone — a $99/year Apple Developer account.

**2. Make the prototype a real web app.** React or Next plus the same Supabase
backend; the schema and RPCs do not change. Much faster to get in front of
students, and distribution is a URL instead of TestFlight. **But a browser
cannot do background geofencing.** Users would have to open the site and tap to
check in, which is the one thing the product exists to avoid. A PWA does not
fix this; the Geolocation API does not run when the tab is closed. If you take
this route, be honest that you are building a different, weaker product — or
treat it as a way to test demand before paying for the iOS path.

**3. Keep the backend, rewrite the client in React Native or Flutter.** Real
geofencing, one codebase, Android too. You throw away the SwiftUI work but keep
the tested backend, which is the larger half.

## Landmines

**Stetson East and Stetson West are ~50 metres apart.** Their geofences overlap
and iOS will fire both. `LocationService.swift` treats a region entry as a
*hint*: it takes a fresh fix and checks the user into whichever hall is
actually nearest. Exits do the same, because leaving Stetson East usually means
walking into Stetson West. Do not "simplify" this away.

**iOS does not guarantee region exit events.** The app re-checks on launch and
on significant location changes, and `checkins.auto_expires_at` kills a
forgotten check-in after three hours. Keep all three; each one catches cases
the others miss.

**Always location permission is non-negotiable.** With "While Using", iOS will
not wake the app and the product does not work. The onboarding has to earn this
permission, and right now it only explains it — that flow deserves real design
attention, because a user who taps "While Using" has a broken app and will not
know why.

**Sign in with Apple and push notifications are both paid entitlements.** This
is why signup is by phone number. Until someone pays the $99, invites only
notify while the app is running or during an iOS background refresh window,
which is not often. The `device_tokens` table and the `alerts_since` function
already exist so switching to APNs is a server-side change, not a redesign.

**Phone auth costs nothing in development.** Supabase has a "Test phone
numbers" feature: map a number to a fixed code and no SMS is sent. Twilio is
only needed for real users.

**No third-party Swift packages, on purpose.** `Services/Backend.swift` is a
hand-written Supabase client — auth, token refresh, RPC — in about 260 lines.
It was written this way because the app could not be compiled to debug an SDK
version mismatch. If you would rather use `supabase-swift`, that is a
reasonable trade now that you can build; the call sites are all in `AppStore`.

**Access rules live in Postgres, not the app.** Every read goes through an RPC
or an RLS policy. The privacy model is essentially one policy — `checkins_read`
in `0002_security.sql`. Keep it that way: a client-side filter is a leak
waiting to happen.

## Open questions nobody has answered yet

- **The cold start.** Day one a user has no friends and an empty list. Hall
  busyness is the only thing that works solo, and it reads low until adoption.
  Menus and hours scraped from NUDining would help; nobody has built that.
- **The share link** (`tray.app/add/<username>`) needs a real domain and an
  `apple-app-site-association` file before it opens the app. Today it is just a
  username to paste into search.
- **Busyness has no good data source.** Northeastern publishes no live capacity
  feed and Google's Popular Times has no public API. Current approach is
  anonymous counts of Tray users, bucketed so a number never identifies anyone
  in a half-empty hall.
- **One campus.** The schema is multi-campus; the seed and signup are not.
- **Nothing has been tested with real students.** Every interaction decision in
  here is reasoned, not validated.

## Getting started in ten minutes

1. Open **https://rargulkar-arch.github.io/tray/** and tap through it. That is
   the product. The source is one file: `prototype/index.html`.
2. Make a free Supabase project, run the six migrations and the seed from the
   SQL editor in order, and turn on phone auth with a test number.
3. Then pick a direction above.
