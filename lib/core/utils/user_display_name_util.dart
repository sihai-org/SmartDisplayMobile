import 'package:supabase_flutter/supabase_flutter.dart';

String resolveUserDisplayName(User? user, {String fallback = ''}) {
  final metadataUsername = (user?.userMetadata?['user_name'] as String?)?.trim();
  if (metadataUsername != null && metadataUsername.isNotEmpty) {
    return metadataUsername;
  }

  final metadataName = (user?.userMetadata?['name'] as String?)?.trim();
  if (metadataName != null && metadataName.isNotEmpty) {
    return metadataName;
  }

  final email = user?.email?.trim();
  if (email != null && email.isNotEmpty) {
    return email;
  }

  return fallback;
}
