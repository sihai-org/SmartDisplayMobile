class BleLogMasker {
  static const _maskedKeys = {'password', 'otpToken'};

  static Object? mask(Object? value) {
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, entryValue) {
        final field = key.toString();
        if (_maskedKeys.contains(field)) {
          result[field] = {'length': _valueLength(entryValue)};
        } else {
          result[field] = mask(entryValue);
        }
      });
      return result;
    }

    if (value is List) {
      return value.map(mask).toList(growable: false);
    }

    return value;
  }

  static int? _valueLength(Object? value) {
    if (value is String) return value.length;
    if (value is List || value is Map) return (value as dynamic).length as int;
    return null;
  }
}
