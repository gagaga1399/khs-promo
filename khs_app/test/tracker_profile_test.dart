import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/tracker_entry.dart';
import 'package:khs/models/tracker_profile.dart';

void main() {
  group('TrackerProfile', () {
    test('roundtrips hidden and custom trackers through JSON', () {
      final profile = TrackerProfile(
        id: 'p1',
        name: 'Аня',
        hidden: {'читать'},
        custom: const [
          CustomTracker(name: 'тренировка', kind: TrackerPropertyKind.boolean),
          CustomTracker(name: 'сон', kind: TrackerPropertyKind.number),
        ],
      );

      final restored = TrackerProfile.fromJson(profile.toJson());

      expect(restored.id, 'p1');
      expect(restored.name, 'Аня');
      expect(restored.hidden, {'читать'});
      expect(restored.custom.length, 2);
      expect(restored.custom.first.name, 'тренировка');
      expect(restored.custom.first.kind, TrackerPropertyKind.boolean);
      expect(restored.custom.last.kind, TrackerPropertyKind.number);
    });

    test('hasCustom finds a tracker by name', () {
      final profile = TrackerProfile(id: 'p', name: 'Я');
      expect(profile.hasCustom('сон'), isFalse);
      profile.custom.add(
        const CustomTracker(name: 'сон', kind: TrackerPropertyKind.number),
      );
      expect(profile.hasCustom('сон'), isTrue);
    });
  });

  group('CustomTracker', () {
    test('unknown kind falls back to boolean', () {
      final tracker = CustomTracker.fromJson({'name': 'x', 'kind': 'нет-такого'});
      expect(tracker.kind, TrackerPropertyKind.boolean);
    });
  });
}
