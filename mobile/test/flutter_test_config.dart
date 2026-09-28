// Loads the app's real fonts before any test runs, so layout tests measure
// Nunito and Nunito Sans rather than Flutter's wide placeholder test font.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Nunito', ['Nunito-SemiBold.ttf', 'Nunito-Bold.ttf', 'Nunito-ExtraBold.ttf', 'Nunito-Black.ttf']);
  await load('NunitoSans', [
    'NunitoSans-Regular.ttf',
    'NunitoSans-Medium.ttf',
    'NunitoSans-SemiBold.ttf',
    'NunitoSans-Bold.ttf',
  ]);
  await testMain();
}
