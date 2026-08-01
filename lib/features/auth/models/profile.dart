import '../../../core/vocabulary/fc_vocabulary.dart';

class Profile {
  const Profile({
    required this.id,
    this.gender,
    this.wearsAccessories,
    this.displayName,
  });

  final String id;

  /// Null until onboarding completes. The row is created by a database trigger at signup, so a
  /// brand-new account always has a profile with no gender — and that null is precisely the signal
  /// the app uses to route to onboarding. It is not an error state.
  final FcGender? gender;

  /// Asked only of male users (PRD §4.1). Null means never asked; the backend treats null the same
  /// as false and shows no accessory recommendations.
  final bool? wearsAccessories;

  final String? displayName;

  bool get needsOnboarding => gender == null;

  /// True once the male branch of onboarding is also settled. A male user who selected their
  /// gender but backed out before the accessory question is still mid-onboarding.
  bool get isOnboardingComplete =>
      gender != null && (gender != FcGender.male || wearsAccessories != null);

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        gender: FcGender.fromWire(json['gender'] as String?),
        wearsAccessories: json['wears_accessories'] as bool?,
        displayName: json['display_name'] as String?,
      );

  Profile copyWith({FcGender? gender, bool? wearsAccessories, String? displayName}) =>
      Profile(
        id: id,
        gender: gender ?? this.gender,
        wearsAccessories: wearsAccessories ?? this.wearsAccessories,
        displayName: displayName ?? this.displayName,
      );
}
