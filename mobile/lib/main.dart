import 'package:flutter/material.dart';

import 'data/store.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load();
  runApp(NutrimeterApp(state: state));
  // Parse the ~6,000-food CNF off the startup path; the picker shows it once ready.
  state.loadCnf();
}
