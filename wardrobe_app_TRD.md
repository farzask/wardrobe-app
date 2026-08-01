# Outfit Planner App — Technical Requirements Document (TRD)

## 1. Architecture Overview

```
┌─────────────────────┐        ┌──────────────────────────┐        ┌───────────────────────┐
│   Flutter App        │        │   Python Backend          │        │   Supabase              │
│   (iOS / Android)     │        │   (FastAPI)                │        │                          │
│                       │        │                            │        │                          │
│  Views ──► ViewModels │◄──────►│  /extract-attributes       │───────►│  Storage (thumbnails)   │
│  (Provider)           │  HTTP  │  /evaluate-outfit          │  writes│  Postgres (attributes,  │
│  ▲                    │        │  - attribute classifier    │        │   users, outfits)       │
│  │                    │        │  - thumbnail generator     │        │  Auth                   │
│  └── Supabase SDK ────┼───────────────────────────────────────────► │  Row Level Security     │
│      (direct reads/    │        │                            │        │                          │
│       writes for CRUD) │        │                            │        │                          │
└─────────────────────┘        └──────────────────────────┘        └───────────────────────┘
```

- Flutter talks to Supabase directly for standard CRUD (reading wardrobe, writing outfits).
- Flutter talks to the Python backend only for two heavy operations: attribute extraction and outfit evaluation.
- The Python backend writes the final thumbnail + attribute payload; Flutter persists the row to Supabase (or the backend does it directly — either works, recommend backend does it so the mobile client never handles raw model output).

## 2. Tech Stack
- **Client:** Flutter, Provider, MVVM
- **Backend:** Python, FastAPI
- **Database/Storage/Auth:** Supabase (Postgres, Storage, Auth, Row Level Security)
- **ML model:** fine-tuned lightweight CNN (EfficientNet-B0 or MobileNetV3) on a DeepFashion2-style attribute taxonomy — small enough for CPU inference at this user scale, no GPU hosting cost required
- **Hosting for backend:** Railway (or Render/Fly.io as alternatives)

## 3. Data Model (Supabase Postgres)

**profiles**
| field | type | notes |
|---|---|---|
| id | uuid | FK → auth.users |
| gender | enum(male, female) | set at onboarding |
| wears_accessories | boolean (nullable) | asked only if gender = male; gates the accessory recommendation path |
| display_name | text | |
| created_at | timestamptz | |

**wardrobe_items**
| field | type | notes |
|---|---|---|
| id | uuid | |
| user_id | uuid | FK → profiles |
| category | text | shirt, kurta, frock, trouser, jeans, shoes, jacket, dupatta, accessory, etc. |
| style | text | button-down, polo, A-line, etc. |
| primary_color | text | |
| secondary_color | text (nullable) | |
| color_hex | text | dominant color, used in compatibility scoring |
| pattern | text | solid, striped, plaid, floral, printed |
| fabric | text | cotton, denim, silk, linen, etc. |
| sleeve_type | text (nullable) | full, half, sleeveless |
| neckline | text (nullable) | round, v-neck, collar |
| fit | text | slim, regular, loose |
| season | text | summer, winter, all-season |
| occasion | text | casual, formal, party, religious/cultural |
| thumbnail_url | text | Supabase Storage path |
| created_at | timestamptz | |

**outfits**
| field | type | notes |
|---|---|---|
| id | uuid | |
| user_id | uuid | FK → profiles |
| name | text (nullable) | |
| occasion | text | |
| compatibility_score | int | 0–100 |
| ai_feedback | text | which item is the weak link + suggestion |
| source | text | 'wardrobe_build' or 'photo_upload' |
| created_at | timestamptz | |

**outfit_items** (join table)
| field | type |
|---|---|
| outfit_id | uuid |
| wardrobe_item_id | uuid |

**style_recommendations**
| field | type | notes |
|---|---|---|
| id | uuid | |
| outfit_id | uuid | FK → outfits |
| type | text | makeup / jewelry / accessory |
| suggestion_text | text | |

## 4. Attribute Extraction Pipeline
1. Flutter captures/picks image → multipart POST to `/extract-attributes` on the Python backend.
2. Backend loads image into memory (never written to Supabase at this stage).
3. Classifier predicts: category, style, primary/secondary color, pattern, fabric, sleeve, neckline, fit.
4. Backend crops to the garment bounding box, generates a WebP thumbnail (~320px width, quality 65–75, target ≤30KB).
5. Backend uploads the thumbnail to Supabase Storage: `wardrobe-thumbnails/{user_id}/{item_id}.webp`.
6. Backend returns `{ attributes, thumbnail_url }` to Flutter.
7. Flutter shows the attributes for user review/edit, then writes the `wardrobe_items` row via the Supabase Dart SDK.
8. The original full-resolution image is discarded from backend memory/temp storage at the end of step 4 — never persisted.

## 5. Storage Optimization Summary
- Per item: ~25–30KB thumbnail + ~1–2KB attribute row ≈ 27–32KB total, vs. 2–4MB for a raw photo.
- At 10 users × 150 items: ~40MB total storage — fits inside Supabase's free tier (500MB DB / 1GB file storage) with large headroom.
- No original images are retained anywhere in the pipeline.

## 6. Outfit Compatibility Engine
Runs in the Python backend (`/evaluate-outfit`), rule-based at launch since no labeled compatibility dataset exists yet for this app:
- **Color harmony:** HSV-distance check between item `color_hex` values — flags clashing hues, rewards complementary/analogous/monochrome palettes.
- **Category/occasion coherence:** flags mismatches (e.g., formal top + casual bottom).
- **Pattern clash rule:** flags more than one bold/printed pattern in the same outfit.
- **Season/fit coherence:** flags mismatched season pairings (e.g., winter jacket + summer shorts).
- Scores are aggregated into a 0–100 compatibility score; the lowest-scoring rule contributor is surfaced as the "weak link" item in `ai_feedback`, with a suggested swap pulled from the user's own wardrobe (same category, different color/pattern that would pass the rule that failed).
- **Future upgrade path:** once enough outfit ratings/history exist, replace or augment the rule engine with an embedding-based compatibility model (e.g., a small siamese network over item attribute embeddings), rather than starting there with no training data.

## 7. Gender-Conditional Recommendation Engine
Runs alongside outfit evaluation, branching on `profiles.gender`. Rule/lookup-based (not ML) at launch:
- **Female:** maps outfit dominant color palette + occasion → a makeup-look category and jewelry-style category from a curated lookup table.
- **Male:** runs only if `profiles.wears_accessories = true`; maps the same inputs (color palette + occasion) → an accessory style category (watch, belt, bracelet, sunglasses) from a curated lookup table.
- Output stored in `style_recommendations`, linked to the `outfit_id`, with `type` = makeup / jewelry / accessory.

## 8. API Contracts (Flutter ↔ Python backend)

**POST /extract-attributes**
- Request: multipart image, user_id
- Response: `{ category, style, primary_color, secondary_color, color_hex, pattern, fabric, sleeve_type, neckline, fit, thumbnail_url }`

**POST /evaluate-outfit**
- Request: `{ user_id, wardrobe_item_ids[] }` (path a) or `{ user_id, image }` (path b)
- Response: `{ compatibility_score, weak_item_id, suggestion_text, recommendations: [{ type, suggestion_text }] }` (recommendations array populated for female users, and for male users only if `wears_accessories = true`)

## 9. Security
- Supabase Row Level Security on every table: `user_id = auth.uid()` for select/insert/update/delete.
- Storage bucket policies scoped per-user path prefix (`{user_id}/...`).
- Python backend authenticates Flutter requests via the Supabase-issued JWT, validated on each call.

## 10. Flutter Folder Structure (MVVM, feature-based, per existing conventions)
```
lib/
  core/
    services/       supabase_service.dart, camera_service.dart, backend_api_service.dart
    widgets/
    utils/
  features/
    onboarding/
      views/         gender_select_view.dart
    auth/
      views/         signup_view.dart, login_view.dart
      viewmodels/     auth_viewmodel.dart
    wardrobe/
      views/         wardrobe_home_view.dart, item_camera_view.dart, item_detail_view.dart
      viewmodels/     wardrobe_viewmodel.dart
      models/         wardrobe_item_model.dart
    outfit/
      views/         outfit_builder_view.dart, outfit_result_view.dart
      viewmodels/     outfit_viewmodel.dart
      models/         outfit_model.dart
  main.dart
```

## 11. Non-Functional Requirements
- Attribute extraction: target a few seconds per item on CPU inference.
- Offline: wardrobe browsing works from local cache; adding items and evaluating outfits require connectivity.
- Scale target: friends/family user count (tens of users), not public-scale — Supabase free tier is sufficient per Section 5 math.

## 12. Risks / Technical Considerations
- Classifier accuracy on non-Western garment categories (kurta, shalwar kameez) depends on training data — DeepFashion2's taxonomy is Western-garment-heavy, so the category/style label set will need custom classes and likely some fine-tuning data collected from the target wardrobe styles.
- Background removal/cropping quality affects both thumbnail usefulness and classifier accuracy — needs a dedicated preprocessing step, not an afterthought.
- Rule-based compatibility scoring will need real-world tuning against actual outfit judgments before it feels "right" — treat initial rule weights as a first draft.
