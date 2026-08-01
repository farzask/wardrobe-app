/// Closed vocabularies — the Dart half of the contract.
///
/// These MUST stay identical to `supabase/migrations/001_enums.sql` and
/// `backend/app/vocabulary.py`. Drift is the highest-probability silent failure in the system: a
/// value the user can pick here but that Postgres does not accept fails on save, on the one screen
/// PRD §8 identifies as the abandonment risk.
///
/// `backend/tests/test_vocabulary_parity.py` parses this file and fails if it disagrees with the
/// SQL, so drift breaks CI rather than production. That test reads the `wire:` values — keep the
/// declaration style below intact.
///
/// `wire` is the database value. `label` is what the user reads. They are deliberately separate:
/// the database value can never change without a migration, but copy changes freely.
library;

enum FcGender {
  male(wire: 'male', label: 'Male'),
  female(wire: 'female', label: 'Female');

  const FcGender({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcGender? fromWire(String? value) =>
      value == null ? null : values.firstWhere((e) => e.wire == value);
}

enum FcCategory {
  shirt(wire: 'shirt', label: 'Shirt'),
  tshirt(wire: 'tshirt', label: 'T-shirt'),
  kurta(wire: 'kurta', label: 'Kurta'),
  kameez(wire: 'kameez', label: 'Kameez'),
  blouse(wire: 'blouse', label: 'Blouse'),
  frock(wire: 'frock', label: 'Frock'),
  dress(wire: 'dress', label: 'Dress'),
  abaya(wire: 'abaya', label: 'Abaya'),
  waistcoat(wire: 'waistcoat', label: 'Waistcoat'),
  jacket(wire: 'jacket', label: 'Jacket'),
  coat(wire: 'coat', label: 'Coat'),
  sweater(wire: 'sweater', label: 'Sweater'),
  trouser(wire: 'trouser', label: 'Trousers'),
  jeans(wire: 'jeans', label: 'Jeans'),
  shalwar(wire: 'shalwar', label: 'Shalwar'),
  skirt(wire: 'skirt', label: 'Skirt'),
  shorts(wire: 'shorts', label: 'Shorts'),
  dupatta(wire: 'dupatta', label: 'Dupatta'),
  scarf(wire: 'scarf', label: 'Scarf'),
  shoes(wire: 'shoes', label: 'Shoes'),
  sandals(wire: 'sandals', label: 'Sandals'),
  heels(wire: 'heels', label: 'Heels'),
  accessory(wire: 'accessory', label: 'Accessory');

  const FcCategory({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcCategory fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);

  FcSlot get slot => kCategorySlot[this]!;
}

enum FcOccasion {
  casual(wire: 'casual', label: 'Casual'),
  formal(wire: 'formal', label: 'Formal'),
  party(wire: 'party', label: 'Party'),
  cultural(wire: 'cultural', label: 'Cultural');

  const FcOccasion({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcOccasion fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);
}

enum FcPattern {
  solid(wire: 'solid', label: 'Solid'),
  striped(wire: 'striped', label: 'Striped'),
  plaid(wire: 'plaid', label: 'Plaid'),
  floral(wire: 'floral', label: 'Floral'),
  printed(wire: 'printed', label: 'Printed');

  const FcPattern({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcPattern fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);
}

enum FcSeason {
  summer(wire: 'summer', label: 'Summer'),
  winter(wire: 'winter', label: 'Winter'),
  allSeason(wire: 'all_season', label: 'All season');

  const FcSeason({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcSeason fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);
}

enum FcFit {
  slim(wire: 'slim', label: 'Slim'),
  regular(wire: 'regular', label: 'Regular'),
  loose(wire: 'loose', label: 'Loose');

  const FcFit({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcFit fromWire(String value) => values.firstWhere((e) => e.wire == value);
}

enum FcSleeveType {
  full(wire: 'full', label: 'Full sleeve'),
  half(wire: 'half', label: 'Half sleeve'),
  sleeveless(wire: 'sleeveless', label: 'Sleeveless');

  const FcSleeveType({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcSleeveType? fromWire(String? value) =>
      value == null ? null : values.firstWhere((e) => e.wire == value);
}

enum FcNeckline {
  round(wire: 'round', label: 'Round'),
  vNeck(wire: 'v_neck', label: 'V-neck'),
  collar(wire: 'collar', label: 'Collar');

  const FcNeckline({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcNeckline? fromWire(String? value) =>
      value == null ? null : values.firstWhere((e) => e.wire == value);
}

enum FcSlot {
  top(wire: 'top', label: 'Top'),
  bottom(wire: 'bottom', label: 'Bottom'),
  fullBody(wire: 'full_body', label: 'Full body'),
  outerwear(wire: 'outerwear', label: 'Outerwear'),
  footwear(wire: 'footwear', label: 'Footwear'),
  drape(wire: 'drape', label: 'Drape'),
  accessory(wire: 'accessory', label: 'Accessory');

  const FcSlot({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcSlot fromWire(String value) => values.firstWhere((e) => e.wire == value);
}

enum FcOutfitSource {
  wardrobeBuild(wire: 'wardrobe_build', label: 'Built from wardrobe'),
  photoUpload(wire: 'photo_upload', label: 'From a photo');

  const FcOutfitSource({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcOutfitSource fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);
}

enum FcItemStatus {
  pendingReview(wire: 'pending_review', label: 'Awaiting review'),
  active(wire: 'active', label: 'Active');

  const FcItemStatus({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcItemStatus fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);
}

enum FcRecommendationType {
  makeup(wire: 'makeup', label: 'Makeup'),
  jewelry(wire: 'jewelry', label: 'Jewellery'),
  accessory(wire: 'accessory', label: 'Accessories');

  const FcRecommendationType({required this.wire, required this.label});
  final String wire;
  final String label;

  static FcRecommendationType fromWire(String value) =>
      values.firstWhere((e) => e.wire == value);
}

/// Mirrors `003_category_slots.sql`. The outfit builder groups by slot, not by category, so that
/// a kurta and a shirt compete for the same position — which is what makes "swap this for that"
/// a meaningful offer.
const Map<FcCategory, FcSlot> kCategorySlot = {
  FcCategory.shirt: FcSlot.top,
  FcCategory.tshirt: FcSlot.top,
  FcCategory.kurta: FcSlot.top,
  FcCategory.kameez: FcSlot.top,
  FcCategory.blouse: FcSlot.top,
  FcCategory.frock: FcSlot.fullBody,
  FcCategory.dress: FcSlot.fullBody,
  FcCategory.abaya: FcSlot.fullBody,
  FcCategory.waistcoat: FcSlot.outerwear,
  FcCategory.jacket: FcSlot.outerwear,
  FcCategory.coat: FcSlot.outerwear,
  FcCategory.sweater: FcSlot.outerwear,
  FcCategory.trouser: FcSlot.bottom,
  FcCategory.jeans: FcSlot.bottom,
  FcCategory.shalwar: FcSlot.bottom,
  FcCategory.skirt: FcSlot.bottom,
  FcCategory.shorts: FcSlot.bottom,
  FcCategory.dupatta: FcSlot.drape,
  FcCategory.scarf: FcSlot.drape,
  FcCategory.shoes: FcSlot.footwear,
  FcCategory.sandals: FcSlot.footwear,
  FcCategory.heels: FcSlot.footwear,
  FcCategory.accessory: FcSlot.accessory,
};
