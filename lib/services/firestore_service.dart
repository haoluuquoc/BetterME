import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Firestore Service - Đồng bộ dữ liệu lên cloud theo uid
class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Lấy uid hiện tại, null nếu chưa đăng nhập
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Reference đến document user hiện tại
  DocumentReference? get _userDoc {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  // ==================== THÔNG TIN TÀI KHOẢN ====================

  /// Lưu email + provider vào Firestore để dễ quản lý
  Future<void> saveUserMeta({String? username}) async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Lấy provider đầu tiên (ưu tiên không phải firebase)
      String provider = 'unknown';
      for (final info in user.providerData) {
        if (info.providerId != 'firebase') {
          provider = info.providerId;
          break;
        }
      }
      
      final meta = <String, dynamic>{
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'provider': provider,
        'lastLogin': FieldValue.serverTimestamp(),
      };

      final normalizedUsername = username?.trim();
      if (normalizedUsername != null && normalizedUsername.isNotEmpty) {
        meta['username'] = normalizedUsername;
        meta['usernameLower'] = normalizedUsername.toLowerCase();
      }

      await doc.set(meta, SetOptions(merge: true));

      // Save reverse-lookup for username-based login
      if (normalizedUsername != null && normalizedUsername.isNotEmpty && user.email != null) {
        await _db.collection('usernames').doc(normalizedUsername.toLowerCase()).set({
          'email': user.email,
          'uid': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Firestore saveUserMeta error: $e');
    }
  }

  // ==================== HỒ SƠ NGƯỜI DÙNG ====================

  /// Lưu hồ sơ người dùng
  Future<void> saveProfile(Map<String, dynamic> data) async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      await doc.set({'profile': data}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore saveProfile error: $e');
    }
  }

  /// Đọc hồ sơ người dùng
  Future<Map<String, dynamic>?> loadProfile() async {
    final doc = _userDoc;
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>?;
        return data?['profile'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('Firestore loadProfile error: $e');
    }
    return null;
  }

  // ==================== UỐNG NƯỚC ====================

  /// Lưu dữ liệu uống nước theo ngày
  Future<void> saveWaterDaily({
    required String dateKey,
    required int totalMl,
    required int goalMl,
    required List<Map<String, dynamic>> entries,
  }) async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      final entriesData = entries.map((e) => {
        'timestamp': (e['time'] as DateTime).millisecondsSinceEpoch,
        'amount': e['amount'],
      }).toList();

      // Đọc giá trị cũ của ngày này để tính delta
      final dayDoc = doc.collection('water_daily').doc(dateKey);
      final oldSnap = await dayDoc.get();
      final oldTotalMl = oldSnap.exists ? (oldSnap.data()?['totalMl'] ?? 0) as int : 0;
      final delta = totalMl - oldTotalMl;

      await dayDoc.set({
        'totalMl': totalMl,
        'goalMl': goalMl,
        'entries': entriesData,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Cập nhật tổng lượng nước trên user document
      if (delta != 0) {
        await doc.set({
          'totalWaterMl': FieldValue.increment(delta),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Firestore saveWaterDaily error: $e');
    }
  }

  /// Đọc dữ liệu uống nước theo ngày
  Future<Map<String, dynamic>?> loadWaterDaily(String dateKey) async {
    final doc = _userDoc;
    if (doc == null) return null;
    try {
      final snap = await doc.collection('water_daily').doc(dateKey).get();
      if (snap.exists) return snap.data();
    } catch (e) {
      debugPrint('Firestore loadWaterDaily error: $e');
    }
    return null;
  }

  /// Đọc lịch sử uống nước 7 ngày
  Future<List<Map<String, dynamic>>> loadWaterHistory(int days) async {
    final doc = _userDoc;
    if (doc == null) return [];
    try {
      final now = DateTime.now();
      final results = <Map<String, dynamic>>[];
      for (int i = 1; i <= days; i++) {
        final date = now.subtract(Duration(days: i));
        final key = _dateKey(date);
        final snap = await doc.collection('water_daily').doc(key).get();
        results.add({
          'date': date,
          'amount': snap.exists ? (snap.data()?['totalMl'] ?? 0) : 0,
        });
      }
      return results.reversed.toList();
    } catch (e) {
      debugPrint('Firestore loadWaterHistory error: $e');
    }
    return [];
  }

  // ==================== CHI TIÊU ====================

  /// Lưu tất cả giao dịch
  Future<void> saveTransactions(List<Map<String, dynamic>> transactions) async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      final data = transactions.map((t) => {
        'type': t['type'],
        'amount': t['amount'],
        'category': t['category'],
        'note': t['note'] ?? '',
        'date': (t['date'] as DateTime).millisecondsSinceEpoch,
      }).toList();

      await doc.set({'transactions': data}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore saveTransactions error: $e');
    }
  }

  /// Đọc tất cả giao dịch
  Future<List<Map<String, dynamic>>> loadTransactions() async {
    final doc = _userDoc;
    if (doc == null) return [];
    try {
      final snap = await doc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>?;
        final list = data?['transactions'] as List<dynamic>?;
        if (list != null) {
          return list.map((t) => {
            'type': t['type'] as String,
            'amount': (t['amount'] as num).toDouble(),
            'category': t['category'] as String,
            'note': t['note'] as String? ?? '',
            'date': DateTime.fromMillisecondsSinceEpoch(t['date'] as int),
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('Firestore loadTransactions error: $e');
    }
    return [];
  }

  // ==================== CẬP NHẬT ỨNG DỤNG ====================

  /// Kiểm tra phiên bản mới từ Firestore
  /// Document: app_config/latest_update
  /// Fields: version, buildNumber, downloadUrl, notes, code
  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      debugPrint('checkForUpdate: reading app_config/latest_update...');
      final doc = await _db.collection('app_config').doc('latest_update').get();
      debugPrint('checkForUpdate: doc.exists=${doc.exists}, data=${doc.data()}');
      if (doc.exists) {
        return doc.data();
      }
    } catch (e) {
      debugPrint('Firestore checkForUpdate error: $e');
    }
    return null;
  }

  /// Tạo document update mẫu (chạy 1 lần để khởi tạo)
  Future<void> initUpdateConfig({
    required String version,
    required int buildNumber,
    required String downloadUrl,
    String notes = '',
    String code = '',
  }) async {
    try {
      await _db.collection('app_config').doc('latest_update').set({
        'version': version,
        'buildNumber': buildNumber,
        'downloadUrl': downloadUrl,
        'notes': notes,
        'code': code,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Firestore initUpdateConfig error: $e');
    }
  }

  // ==================== SỨC KHỎE ====================

  /// Lưu dữ liệu sức khỏe hàng ngày (steps, sleep, weight, height)
  Future<void> saveHealthDaily({
    required String dateKey,
    int? steps,
    double? sleepHours,
    double? weightKg,
    double? heightCm,
  }) async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (steps != null) data['steps'] = steps;
      if (sleepHours != null) data['sleepHours'] = sleepHours;
      if (weightKg != null) data['weightKg'] = weightKg;

      await doc.collection('health_daily').doc(dateKey).set(
        data,
        SetOptions(merge: true),
      );

      // Lưu chiều cao vào profile (chiều cao không đổi theo ngày)
      if (heightCm != null) {
        await doc.set({
          'profile': {'heightCm': heightCm},
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Firestore saveHealthDaily error: $e');
    }
  }

  /// Đọc dữ liệu sức khỏe theo ngày
  Future<Map<String, dynamic>?> loadHealthDaily(String dateKey) async {
    final doc = _userDoc;
    if (doc == null) return null;
    try {
      final snap = await doc.collection('health_daily').doc(dateKey).get();
      if (snap.exists) return snap.data();
    } catch (e) {
      debugPrint('Firestore loadHealthDaily error: $e');
    }
    return null;
  }

  /// Đọc lịch sử sức khỏe nhiều ngày (steps, sleep, weight) từ Firestore
  Future<List<Map<String, dynamic>>> loadHealthHistory(int days) async {
    final doc = _userDoc;
    if (doc == null) return [];
    try {
      final now = DateTime.now();
      final results = <Map<String, dynamic>>[];
      for (int i = 0; i < days; i++) {
        final date = now.subtract(Duration(days: i));
        final key = _dateKey(date);
        final snap = await doc.collection('health_daily').doc(key).get();
        if (snap.exists) {
          final data = Map<String, dynamic>.from(snap.data()!);
          data['date'] = key;
          results.add(data);
        }
      }
      return results;
    } catch (e) {
      debugPrint('Firestore loadHealthHistory error: $e');
    }
    return [];
  }

  /// Lưu danh sách sinh nhật
  Future<void> saveBirthdays(List<Map<String, String>> birthdays) async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      final data = birthdays.map((b) => {
        'name': b['name'],
        'date': b['date'],
      }).toList();
      await doc.set({'birthdays': data}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore saveBirthdays error: $e');
    }
  }

  /// Đọc danh sách sinh nhật
  Future<List<Map<String, String>>> loadBirthdays() async {
    final doc = _userDoc;
    if (doc == null) return [];
    try {
      final snap = await doc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>?;
        final list = data?['birthdays'] as List<dynamic>?;
        if (list != null) {
          return list.map((b) => {
            'name': (b['name'] as String?) ?? '',
            'date': (b['date'] as String?) ?? '',
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('Firestore loadBirthdays error: $e');
    }
    return [];
  }

  /// Đọc chiều cao từ profile
  Future<double?> loadHeight() async {
    final doc = _userDoc;
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>?;
        final profile = data?['profile'] as Map<String, dynamic>?;
        return (profile?['heightCm'] as num?)?.toDouble();
      }
    } catch (e) {
      debugPrint('Firestore loadHeight error: $e');
    }
    return null;
  }

  // ==================== BIOMETRIC DEVICE REGISTRATION ====================

  /// Đăng ký thiết bị cho đăng nhập sinh trắc học (lưu lên Firestore)
  Future<void> saveBiometricRegistration({
    required String email,
    required String provider,
  }) async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      await doc.set({
        'biometric': {
          'enabled': true,
          'linkedEmail': email,
          'provider': provider,
          'enabledAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore saveBiometricRegistration error: $e');
    }
  }

  /// Xóa đăng ký sinh trắc học
  Future<void> removeBiometricRegistration() async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      await doc.update({
        'biometric': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('Firestore removeBiometricRegistration error: $e');
    }
  }

  /// Đọc thông tin đăng ký sinh trắc học từ Firestore
  Future<Map<String, dynamic>?> loadBiometricRegistration() async {
    final doc = _userDoc;
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>?;
        final biometric = data?['biometric'] as Map<String, dynamic>?;
        if (biometric != null && biometric['enabled'] == true) {
          return biometric;
        }
      }
    } catch (e) {
      debugPrint('Firestore loadBiometricRegistration error: $e');
    }
    return null;
  }

  /// Lưu credentials đã mã hóa lên Firestore (để khôi phục sau reinstall)
  Future<void> saveBiometricCredentials({
    required String email,
    required String password,
  }) async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      await doc.set({
        'biometric': {
          'savedEmail': email,
          'savedPassword': password,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore saveBiometricCredentials error: $e');
    }
  }

  /// Đọc credentials đã lưu từ Firestore
  Future<Map<String, String>?> loadBiometricCredentials() async {
    final doc = _userDoc;
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>?;
        final biometric = data?['biometric'] as Map<String, dynamic>?;
        if (biometric != null) {
          final email = biometric['savedEmail'] as String?;
          final password = biometric['savedPassword'] as String?;
          if (email != null && password != null) {
            return {'email': email, 'password': password};
          }
        }
      }
    } catch (e) {
      debugPrint('Firestore loadBiometricCredentials error: $e');
    }
    return null;
  }

  /// Xóa credentials khi tắt biometric
  Future<void> removeBiometricCredentials() async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      await doc.update({
        'biometric.savedEmail': FieldValue.delete(),
        'biometric.savedPassword': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('Firestore removeBiometricCredentials error: $e');
    }
  }

  // ==================== HELPER ====================

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
