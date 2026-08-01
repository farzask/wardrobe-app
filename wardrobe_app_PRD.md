# Outfit Planner App — Product Requirements Document (PRD)

## 1. Overview
A Flutter app (iOS + Android) that digitizes a user's wardrobe as structured attribute data instead of raw photos, then helps plan and validate daily outfits. Multi-user, individual accounts (friends/family).

## 2. Problem Statement
- Users own more clothes than they can mentally track, leading to decision fatigue and underused items.
- Existing closet apps store full images per item, which is storage-heavy and slow to scale.
- Users want an outfit "second opinion" without manually knowing color theory or style rules.

## 3. Target Users
- Multi-user product. Each user has an individual account (Supabase Auth).
- No data sharing between accounts in v1 — each wardrobe/outfit set is private to its owner.
- Onboarding asks the user to select **male / female** — this drives which recommendation modules are shown later.

## 4. Core Features (v1 / MVP)

### 4.1 Onboarding
- Signup / login (email + password via Supabase Auth).
- Gender selection (male / female) — required, stored on profile, used to gate the recommendation module in 4.5.
- If male: a follow-up opt-in question — "Do you wear accessories (watches, bracelets, belts, etc.)?" (yes/no). Stored on profile, gates the male accessory recommendation path in 4.5.

### 4.2 Wardrobe Digitization
- User photographs or uploads an image of a clothing item.
- App sends the image to the backend, which extracts structured attributes (category, style, color, pattern, fabric, sleeve, neckline, fit, season, occasion) and generates a small thumbnail.
- Original photo is not kept — only the thumbnail + attributes are saved (see TRD for the storage pipeline).
- User can review/edit the auto-detected attributes before saving (correct a misclassified color, etc.).

### 4.3 Wardrobe Browsing
- Grid view of wardrobe thumbnails.
- Filter/sort by category, color, season, occasion.
- Item detail view shows all extracted attributes.

### 4.4 Outfit Builder & Compatibility Check
Two entry points:
- **(a) Build from wardrobe (primary):** user selects existing digitized items (top, bottom, footwear, etc.) to form an outfit. Compatibility is computed directly from stored attributes — no new image processing needed.
- **(b) Upload a standalone outfit photo:** user uploads a photo of an outfit not yet in their digitized wardrobe (e.g., a flat-lay or full photo). Backend detects and attributes each garment, then evaluates.

Output for both paths:
- A compatibility score.
- If suboptimal: which specific item is the weak link, and 1–2 concrete alternative suggestions (swap X for a different color/category from the user's own wardrobe).

### 4.5 Gender-Based Styling Recommendations
Shown alongside outfit evaluation (4.4), branching by profile gender:

**Female:**
- Suggests a makeup look category (e.g., natural/daytime vs. bold/evening) based on the outfit's color palette and occasion.
- Suggests jewelry style (minimal vs. statement) based on the same inputs.

**Male (only if opted in at onboarding, 4.1):**
- Suggests accessory style (watch, belt, bracelet, sunglasses) matched to the outfit's color palette, formality, and occasion.
- Not shown at all if the user indicated at signup that they don't wear accessories.

## 5. Key User Flows
1. **Sign up → select gender → land on empty wardrobe**
2. **Add item:** camera/gallery → attribute extraction → review/edit → save
3. **Plan an outfit:** select items from wardrobe → get compatibility score + feedback → (if female) get makeup/jewelry suggestion
4. **Ad-hoc outfit check:** upload outfit photo → same evaluation flow as above

## 6. Non-Functional Requirements
- Attribute extraction should complete in a few seconds per item (perceived responsiveness matters more than exact benchmark).
- Wardrobe browsing must work with cached data when offline; adding new items requires connectivity (backend call).
- Each user's data is isolated and private by default.

## 7. Explicitly Out of Scope (v1)
- Sharing wardrobes/outfits between accounts.
- Virtual try-on / AR visualization.
- Shopping integration or purchase links.
- Male-specific styling recommendation module (not requested).
- Laundry/wear-tracking or cost-per-wear analytics (not requested).

## 8. Success Signals (informal, personal/friends-family scale)
- Item digitization is fast and accurate enough that users don't abandon the attribute-review step.
- Outfit feedback is specific enough (names the weak item) that users trust and act on it.

## 9. Open Questions
- Should outfit history be tracked to flag repeats? (Not requested — flagging as a natural v2 candidate.)
- Any occasion presets needed beyond casual/formal/party (e.g., religious/cultural wear — kurta, shalwar kameez)?
