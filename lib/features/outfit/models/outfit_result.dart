import '../../../core/vocabulary/fc_vocabulary.dart';

/// A suggested replacement for the weak item, drawn from the user's own wardrobe (PRD §4.4).
class SwapSuggestion {
  const SwapSuggestion({
    required this.replacementItemId,
    required this.replacesItemId,
    required this.newScore,
    required this.delta,
    required this.reason,
  });

  final String replacementItemId;
  final String replacesItemId;
  final int newScore;

  /// Points this swap would add. Always positive — the engine only returns improvements.
  final int delta;
  final String reason;

  factory SwapSuggestion.fromJson(Map<String, dynamic> json) => SwapSuggestion(
        replacementItemId: json['replacement_item_id'] as String,
        replacesItemId: json['replaces_item_id'] as String,
        newScore: json['new_score'] as int,
        delta: json['delta'] as int,
        reason: json['reason'] as String,
      );
}

class StyleRecommendation {
  const StyleRecommendation({required this.type, required this.suggestionText});

  final FcRecommendationType type;
  final String suggestionText;

  factory StyleRecommendation.fromJson(Map<String, dynamic> json) =>
      StyleRecommendation(
        type: FcRecommendationType.fromWire(json['type'] as String),
        suggestionText: json['suggestion_text'] as String,
      );
}

class OutfitResult {
  const OutfitResult({
    required this.score,
    required this.suggestionText,
    required this.rulesetVersion,
    this.weakItemId,
    this.suggestions = const [],
    this.recommendations = const [],
    this.completenessWarning,
    this.outfitId,
  });

  final int score;

  /// The item the engine identified as dragging the outfit down. **Null means the outfit is
  /// genuinely fine** — not "unknown". The result screen must render the two cases differently, or
  /// it will invent a problem the engine did not find.
  final String? weakItemId;

  final String suggestionText;
  final List<SwapSuggestion> suggestions;

  /// Empty for a male user who opted out of accessories (PRD §4.5), and for a profile that has not
  /// finished onboarding. The result screen omits the whole card rather than showing an empty one.
  final List<StyleRecommendation> recommendations;

  /// "This outfit has no bottom." Deliberately separate from the score: a missing garment is not a
  /// compatibility problem, and folding it in would make the 0–100 mean two things at once.
  final String? completenessWarning;

  /// Pinned so a later retune of the rules cannot silently change what a stored score meant.
  final String rulesetVersion;
  final String? outfitId;

  bool get isGood => weakItemId == null;

  factory OutfitResult.fromJson(Map<String, dynamic> json) => OutfitResult(
        score: json['compatibility_score'] as int,
        weakItemId: json['weak_item_id'] as String?,
        suggestionText: json['suggestion_text'] as String,
        suggestions: (json['suggestions'] as List<dynamic>? ?? [])
            .map((e) => SwapSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        recommendations: (json['recommendations'] as List<dynamic>? ?? [])
            .map((e) => StyleRecommendation.fromJson(e as Map<String, dynamic>))
            .toList(),
        completenessWarning: json['completeness_warning'] as String?,
        rulesetVersion: json['ruleset_version'] as String,
        outfitId: json['outfit_id'] as String?,
      );
}
