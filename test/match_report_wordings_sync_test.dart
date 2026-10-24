import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/match_workspace/match_report_wordings.dart';

/// The app's wordings are generated from the JSON the public site reads
/// (decision package 12, PLM-07). A change to one without the other fails
/// here: run node ops/generate_match_report_wordings.mjs.
void main() {
  test('the app words match reports as the public site does', () {
    final json =
        jsonDecode(
              File(
                'public-site/lib/match-report-wordings.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final dart = <String, Object>{
      'intros': reportIntros,
      'assists': reportAssists,
      'goalsUs': reportGoalsUs,
      'goalsThem': reportGoalsThem,
      'shotsUs': reportShotsUs,
      'shotsThem': reportShotsThem,
      'saves': reportSaves,
      'penaltiesUs': reportPenaltiesUs,
      'penaltiesThem': reportPenaltiesThem,
      'cardsUs': reportCardsUs,
      'cardsThem': reportCardsThem,
      'substitutions': reportSubstitutions,
      'injuries': reportInjuries,
    };
    expect(json.keys.where((key) => key != 'about').toSet(), dart.keys.toSet());
    for (final MapEntry(:key, :value) in dart.entries) {
      expect(jsonDecode(jsonEncode(value)), json[key], reason: key);
    }
  });
}
