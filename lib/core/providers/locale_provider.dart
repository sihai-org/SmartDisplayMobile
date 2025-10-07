import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Force English for testing; set to null to follow system by default.
final localeProvider = StateProvider<Locale?>((ref) => const Locale('en'));
