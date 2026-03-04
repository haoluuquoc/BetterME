/// String validation utilities
class Validators {
  Validators._();

  static String? validateRequired(String? value, [String? fieldName]) {
    if (value == null || value.trim().isEmpty) {
      return '${fieldName ?? 'Trường này'} không được để trống';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email không được để trống';
    }
    
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Email không hợp lệ';
    }
    return null;
  }

  static String? validateMinLength(String? value, int minLength, [String? fieldName]) {
    if (value == null || value.length < minLength) {
      return '${fieldName ?? 'Trường này'} phải có ít nhất $minLength ký tự';
    }
    return null;
  }

  static String? validateMaxLength(String? value, int maxLength, [String? fieldName]) {
    if (value != null && value.length > maxLength) {
      return '${fieldName ?? 'Trường này'} không được vượt quá $maxLength ký tự';
    }
    return null;
  }
}
