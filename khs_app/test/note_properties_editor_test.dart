import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/localization/app_strings.dart';
import 'package:khs/models/tracker_entry.dart';
import 'package:khs/ui/widgets/note_properties_editor.dart';

void main() {
  const strings = AppStrings('ru');

  test('convertPropertyValue switches types', () {
    expect(convertPropertyValue('true', TrackerPropertyKind.boolean), true);
    expect(convertPropertyValue('4', TrackerPropertyKind.number), 4);
    expect(convertPropertyValue(5, TrackerPropertyKind.text), '5');
    expect(convertPropertyValue('x', TrackerPropertyKind.list), ['x']);
    expect(convertPropertyValue(['a', 'b'], TrackerPropertyKind.text), 'a, b');
  });

  testWidgets('показывает свойства и переключает да/нет', (tester) async {
    final props = <NotePropertyDraft>[
      NotePropertyDraft(id: 0, key: 'чтение', value: true),
      NotePropertyDraft(id: 1, key: 'самоощущение', value: 4),
      NotePropertyDraft(id: 2, key: 'заметка', value: 'привет'),
    ];
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotePropertiesEditor(
            strings: strings,
            properties: props,
            onChanged: () => changes++,
            onAdd: () {},
            onRemove: (d) => props.remove(d),
          ),
        ),
      ),
    );

    expect(find.text('Свойства'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    final texts = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller?.text)
        .toList();
    expect(texts, contains('чтение'));
    expect(texts, contains('4'));
    expect(texts, contains('привет'));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(props[0].value, false);
    expect(changes, greaterThan(0));
  });

  testWidgets('добавляет пустое свойство и удаляет', (tester) async {
    final props = <NotePropertyDraft>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NotePropertiesEditor(
              strings: strings,
              properties: props,
              onChanged: () {},
              onAdd: () => setState(
                () => props.add(NotePropertyDraft(id: 9, key: '', value: '')),
              ),
              onRemove: (d) => setState(() => props.remove(d)),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Свойств нет'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('Свойств нет'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Свойств нет'), findsOneWidget);
  });
}
