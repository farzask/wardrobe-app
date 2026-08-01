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

See [supabase/SETUP.md](supabase/SETUP.md) for the database and [backend/README.md](backend/README.md)
for the service. Neither has committed credentials; both read from a gitignored `.env`.

## Privacy — read this before shipping

FitCheck does not retain your original photos. It does send them to **Google Gemini** for attribute
extraction, and this build uses Gemini's **free tier**, on which Google may retain submitted content
to improve its products and human reviewers may see it.

That is a deliberate, recorded decision (issue #5 in [skills/README.md](skills/README.md)), and the
in-product copy states it plainly. Switching to a billing-enabled Gemini key removes the third-party
retention — at this app's scale the cost is a few dollars for the app's entire life — and the
disclosure copy can then be dropped.
