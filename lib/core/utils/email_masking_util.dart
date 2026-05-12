class EmailMaskingUtil {
  EmailMaskingUtil._();

  static Map<String, String> toLogParts(String email) {
    final parts = email.trim().toLowerCase().split('@');
    final emailName = parts.isNotEmpty ? parts.first : '';
    final emailHost = parts.length > 1 ? parts.sublist(1).join('@') : '';

    return {'email_name': emailName, 'email_host': emailHost};
  }
}
