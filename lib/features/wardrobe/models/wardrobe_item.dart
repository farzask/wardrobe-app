import 'dart:convert';

import '../../../core/vocabulary/colour_family.dart';
import '../../../core/vocabulary/fc_vocabulary.dart';

/// One weighted colour from an item's palette.
///
/// Exists because a striped or floral garment has no single dominant colour — averaging a
/// red-and-white shirt produces pink, a colour the garment does not contain, which then drives the
/// compatibility engine's harmony rule. Decision #4 in `skills/README.md`.
class PaletteColour {
  const PaletteColour({required this.hex, required this.weight});

  final String hex;

  /// Fraction of the garment's pixels, 0–1. Weights across a palette sum to 1.
  final double weight;

  factory PaletteColour.fromJson(Map<String, dynamic> json) => PaletteColour(
        hex: json['hex'] as String,
        weight: (json['weight'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'hex': hex, 'weight': weight};
}

class WardrobeItem {
  const WardrobeItem({
    required this.id,
    required this.category,
    required this.pattern,
    required this.fit,
    required this.season,
    required this.occasion,
    required this.colorHex,
    required this.palette,
    required this.primaryColor,
    required this.status,
    required this.createdAt,
    this.style,
    this.fabric,
    this.sleeveType,
    this.neckline,
    this.secondaryColor,
    this.thumbnailPath,
    this.extractionConfidence = const {},
  });

  final String id;
  final FcCategory category;
  final FcPattern pattern;
  final FcFit fit;
  final FcSeason season;
  final FcOccasion occasion;

  final String colorHex;
  final List<PaletteColour> palette;
  final String primaryColor;
  final String? secondaryColor;

  final String? style;
  final String? fabric;
  final FcSleeveType? sleeveType;
  final FcNeckline? neckline;

  /// Storage object path, not a URL. Signed URLs expire; a persisted expired URL is a permanently
  /// broken thumbnail, so the path is stored and signed at read time.
  final String? thumbnailPath;

  final FcItemStatus status;
  final DateTime createdAt;

  /// Per-field self-reported confidence from the extractor. Drives the ordering of the review
  /// screen so the user checks the shakiest field first. Not calibrated — see
  /// `backend/app/extraction.py`. Never used to auto-accept anything.
  final Map<String, double> extractionConfidence;

  FcSlot get slot => category.slot;

  /// Which colour drawer this garment belongs in, for the wardrobe filter (PRD §4.3).
  ///
  /// Derived from every palette entry, not just the dominant one: a navy shirt with a broad cream
  /// stripe should turn up under both navy and cream, because the user thinks of it as both.
  Set<FcColourFamily> get colourFamilies => effectivePalette
      // Ignore slivers — a 5% flash of red does not make a shirt a red shirt.
      .where((entry) => entry.weight >= 0.20)
      .map((entry) => FcColourFamily.fromHex(entry.hex))
      .toSet();

  /// The palette rendered as a stripe needs at least one entry. Older rows written before the
  /// palette column existed fall back to the single dominant colour.
  List<PaletteColour> get effectivePalette => palette.isNotEmpty
      ? palette
      : [PaletteColour(hex: colorHex, weight: 1.0)];

  factory WardrobeItem.fromJson(Map<String, dynamic> json) {
    return WardrobeItem(
      id: json['id'] as String,
      category: FcCategory.fromWire(json['category'] as String),
      pattern: FcPattern.fromWire(json['pattern'] as String),
      fit: FcFit.fromWire(json['fit'] as String),
      season: FcSeason.fromWire(json['season'] as String),
      occasion: FcOccasion.fromWire(json['occasion'] as String),
      colorHex: json['color_hex'] as String,
      palette: _decodePalette(json['color_palette']),
      primaryColor: json['primary_color'] as String? ?? json['color_hex'] as String,
      secondaryColor: json['secondary_color'] as String?,
      style: json['style'] as String?,
      fabric: json['fabric'] as String?,
      sleeveType: FcSleeveType.fromWire(json['sleeve_type'] as String?),
      neckline: FcNeckline.fromWire(json['neckline'] as String?),
      thumbnailPath: json['thumbnail_path'] as String?,
      status: FcItemStatus.fromWire(json['status'] as String? ?? 'active'),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      extractionConfidence: _decodeConfidence(json['extraction_confidence']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.wire,
        'pattern': pattern.wire,
        'fit': fit.wire,
        'season': season.wire,
        'occasion': occasion.wire,
        'color_hex': colorHex,
        'color_palette': palette.map((p) => p.toJson()).toList(),
        'primary_color': primaryColor,
        'secondary_color': secondaryColor,
        'style': style,
        'fabric': fabric,
        'sleeve_type': sleeveType?.wire,
        'neckline': neckline?.wire,
        'thumbnail_path': thumbnailPath,
        'status': status.wire,
        'created_at': createdAt.toUtc().toIso8601String(),
        'extraction_confidence': extractionConfidence,
      };

  WardrobeItem copyWith({
    FcCategory? category,
    FcPattern? pattern,
    FcFit? fit,
    FcSeason? season,
    FcOccasion? occasion,
    String? style,
    String? fabric,
    FcSleeveType? sleeveType,
    FcNeckline? neckline,
    FcItemStatus? status,
    bool clearSleeveType = false,
    bool clearNeckline = false,
  }) {
    return WardrobeItem(
      id: id,
      category: category ?? this.category,
      pattern: pattern ?? this.pattern,
      fit: fit ?? this.fit,
      season: season ?? this.season,
      occasion: occasion ?? this.occasion,
      colorHex: colorHex,
      palette: palette,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      style: style ?? this.style,
      fabric: fabric ?? this.fabric,
      // Nullable enums need an explicit clear flag: `?? this.x` cannot express "set this to null",
      // so without it the user could never remove a wrongly-detected neckline.
      sleeveType: clearSleeveType ? null : (sleeveType ?? this.sleeveType),
      neckline: clearNeckline ? null : (neckline ?? this.neckline),
      thumbnailPath: thumbnailPath,
      status: status ?? this.status,
      createdAt: createdAt,
      extractionConfidence: extractionConfidence,
    );
  }

  static List<PaletteColour> _decodePalette(Object? raw) {
    if (raw == null) return const [];
    // Postgres returns jsonb as a List; the SQLite cache stores it as a text blob.
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => PaletteColour.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Map<String, double> _decodeConfidence(Object? raw) {
    if (raw == null) return const {};
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) return const {};
    return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
  }
}
