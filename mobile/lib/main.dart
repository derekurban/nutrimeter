import 'package:flutter/material.dart';

import 'data/store.dart';
import 'services/backend.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load();
  runApp(NutrimeterApp(state: state));
  // Parse the ~6,000-food CNF off the startup path; the picker shows it once ready.
  state.loadCnf();
  // Food review is optional: restore the session, then sync the catalogue and send pending uploads, all off the
  // startup path. Without a connection or an account the app works from its own data.
  Backend.start(state);
}
