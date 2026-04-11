String appendFileExtensionIfMissing(String name, {required String extension}) {
  final normalizedExtension = extension.trim().toLowerCase();
  if (normalizedExtension.isEmpty) {
    return name;
  }

  final suffix = normalizedExtension.startsWith('.')
      ? normalizedExtension
      : '.$normalizedExtension';
  if (name.toLowerCase().endsWith(suffix)) {
    return name;
  }
  return '$name$suffix';
}
