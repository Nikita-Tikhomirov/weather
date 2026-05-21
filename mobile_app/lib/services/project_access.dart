const projectChatOwnerPhone = '79679812438';

String normalizePhoneForAccess(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]+'), '');
  if (digits.length == 11 && digits.startsWith('8')) {
    return '7${digits.substring(1)}';
  }
  return digits;
}

bool canUseProjectChats(String phone) {
  return normalizePhoneForAccess(phone) == projectChatOwnerPhone;
}
