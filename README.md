# FitCheck

Digitize your wardrobe as **structured attributes instead of photos**, then get a second opinion on
any outfit. Built from [wardrobe_app_PRD.md](wardrobe_app_PRD.md) and
[wardrobe_app_TRD.md](wardrobe_app_TRD.md).

## Repository layout

```
lib/                  Flutter app (MVVM + Provider)
supabase/migrations/  Postgres schema, RLS policies, storage policies
backend/              Python FastAPI service (extraction, compatibility, recommendations)
skills/               Engineering process skills — read skills/README.md first
validation/           Requirement traceability matrix
```

## Start here

[skills/README.md](skills/README.md) holds the build DAG, the loop/graph engineering conventions
every other skill refers to, and the running list of decisions and open issues in the source
documents. Nothing in this repo silently resolves a spec contradiction — they are all tracked there.

## Setup

```
cp .env.example .env                    # Flutter — public values only
cp backend/.env.example backend/.env    # Python  — secrets
flutter run                             # no --dart-define needed
```

Full instructions in [supabase/SETUP.md](supabase/SETUP.md) for the database and
[backend/README.md](backend/README.md) for the service. Nothing here has committed credentials.

**The two `.env` files are not interchangeable.** The root one is bundled into the app as an asset
and ships inside the APK, so it holds only `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `BACKEND_URL` —
all public. `SUPABASE_JWT_SECRET` and `GEMINI_API_KEY` live in `backend/.env` and never reach a
client build. The app refuses to launch if it finds a server secret in its own `.env`.

## Privacy — read this before shipping

FitCheck does not retain your original photos. It does send them to **Google Gemini** for attribute
extraction, and this build uses Gemini's **free tier**, on which Google may retain submitted content
to improve its products and human reviewers may see it.

That is a deliberate, recorded decision (issue #5 in [skills/README.md](skills/README.md)), and the
in-product copy states it plainly. Switching to a billing-enabled Gemini key removes the third-party
retention — at this app's scale the cost is a few dollars for the app's entire life — and the
disclosure copy can then be dropped.
