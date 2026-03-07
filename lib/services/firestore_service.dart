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
  Future<void> saveUserMeta() async {
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
      
      await doc.set({
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'provider': provider,
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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

      await doc.collection('water_daily').doc(dateKey).set({
        'totalMl': totalMl,
        'goalMl': goalMl,
        'entries': entriesData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
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

  // ==================== HELPER ====================

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
