import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'firestore_service.dart';
import 'health_service.dart';

/// Authentication Service - Quáº£n lÃ½ Ä‘Äƒng nháº­p/Ä‘Äƒng kÃ½ vá»›i Firebase
class AuthService {
  static const Duration _postLoginMetaTimeout = Duration(seconds: 2);
  static const Duration _postLoginHealthTimeout = Duration(seconds: 4);
  static const Duration _preLogoutSyncTimeout = Duration(seconds: 5);
  static const Duration _googleSignOutTimeout = Duration(seconds: 2);
  /// Kiá»ƒm tra Firebase Ä‘Ã£ Ä‘Æ°á»£c khá»Ÿi táº¡o chÆ°a
  bool get _isFirebaseReady {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  FirebaseAuth get _auth => FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Stream theo dÃµi tráº¡ng thÃ¡i Ä‘Äƒng nháº­p
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// NgÆ°á»i dÃ¹ng hiá»‡n táº¡i
  User? get currentUser => _isFirebaseReady ? _auth.currentUser : null;

  /// Kiá»ƒm tra Ä‘Ã£ Ä‘Äƒng nháº­p chÆ°a
  bool get isLoggedIn => _isFirebaseReady && _auth.currentUser != null;

  // ==================== EMAIL/PASSWORD ====================

  /// ÄÄƒng kÃ½ báº±ng email vÃ  máº­t kháº©u
  Future<AuthResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Cáº­p nháº­t tÃªn hiá»ƒn thá»‹ náº¿u cÃ³
      if (displayName != null && credential.user != null) {
        await credential.user!.updateDisplayName(displayName);
        await credential.user!.reload();
      }

      await _handleUserSwitch(credential.user);
      _startPostLoginTasks();
      return AuthResult.success(user: _auth.currentUser);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'ÄÃ£ xáº£y ra lá»—i: $e');
    }
  }

  /// ÄÄƒng nháº­p báº±ng email vÃ  máº­t kháº©u
  Future<AuthResult> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _handleUserSwitch(credential.user);
      _startPostLoginTasks();
      return AuthResult.success(user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'ÄÃ£ xáº£y ra lá»—i: $e');
    }
  }

  void _startPostLoginTasks() {
    unawaited(_runPostLoginTasks());
  }

  Future<void> _runPostLoginTasks() async {
    await _runWithTimeout(
      FirestoreService().saveUserMeta(),
      timeout: _postLoginMetaTimeout,
      label: 'saveUserMeta',
    );
    await _runWithTimeout(
      HealthService().init(),
      timeout: _postLoginHealthTimeout,
      label: 'healthInit',
    );
  }

  Future<void> _runWithTimeout(
    Future<void> task, {
    required Duration timeout,
    required String label,
  }) async {
    try {
      await task.timeout(timeout);
    } on TimeoutException {
      debugPrint('$label timed out after ${timeout.inSeconds}s');
    } catch (e) {
      debugPrint('$label error: $e');
    }
  }

  // ==================== GOOGLE SIGN IN ======================================

  /// ÄÄƒng nháº­p báº±ng Google
  Future<AuthResult> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return AuthResult.failure(message: 'ÄÄƒng nháº­p Google bá»‹ há»§y');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _handleUserSwitch(userCredential.user);
      _startPostLoginTasks();
      return AuthResult.success(user: userCredential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'Lá»—i Ä‘Äƒng nháº­p Google: $e');
    }
  }

  // ==================== APPLE SIGN IN ====================

  /// ÄÄƒng nháº­p báº±ng Apple
  Future<AuthResult> signInWithApple() async {
    try {
      final appleProvider = AppleAuthProvider();
      appleProvider.addScope('email');
      appleProvider.addScope('name');

      final userCredential = await _auth.signInWithProvider(appleProvider);
      await _handleUserSwitch(userCredential.user);
      _startPostLoginTasks();
      return AuthResult.success(user: userCredential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'Lá»—i Ä‘Äƒng nháº­p Apple: $e');
    }
  }

  // ==================== FORGOT PASSWORD ====================

  /// Gá»­i email Ä‘áº·t láº¡i máº­t kháº©u
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return AuthResult.success(
        message: 'Email Ä‘áº·t láº¡i máº­t kháº©u Ä‘Ã£ Ä‘Æ°á»£c gá»­i Ä‘áº¿n $email',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'ÄÃ£ xáº£y ra lá»—i: $e');
    }
  }

  // ==================== CHANGE PASSWORD ====================

  /// Äá»•i máº­t kháº©u
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ChÆ°a Ä‘Äƒng nháº­p');
    }
    
    if (user.email == null) {
      throw Exception('TÃ i khoáº£n khÃ´ng cÃ³ email (Ä‘Äƒng nháº­p báº±ng Google/Apple)');
    }
    
    // Re-authenticate vá»›i máº­t kháº©u hiá»‡n táº¡i
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw Exception('Máº­t kháº©u hiá»‡n táº¡i khÃ´ng Ä‘Ãºng');
      }
      throw Exception(_getErrorMessage(e.code));
    }
    
    // Äá»•i máº­t kháº©u
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_getErrorMessage(e.code));
    }
  }

  // ==================== SIGN OUT ====================

  Future<void> _clearLocalUserData(SharedPreferences prefs) async {
    // Clear ONLY user-scoped data. Keep app settings like login preferences, theme, notifications.
    final userDataKeys = <String>[
      // Water data
      'water_current_ml', 'water_daily_goal_ml', 'water_last_date',
      'water_today_entries',
      // Steps data
      'steps_today', 'steps_date', 'steps_baseline', 'steps_history',
      'steps_need_rebase', 'steps_rebase_target', 'steps_rebase_date',
      'steps_last_sync_date',
      // Sleep & Weight & Height
      'sleep_history', 'weight_history', 'user_height_cm',
      // Birthdays
      'birthdays',
      // Transactions (chi tiÃªu)
      'expense_transactions',
      // Profile
      'profile_name', 'profile_dob', 'profile_gender', 'profile_phone',
      'profile_height', 'profile_weight', 'profile_location',
      'avatar_path',
      // Alarm state
      'block_alarm_screen', 'pending_water_dialog',
    ];

    for (final key in userDataKeys) {
      await prefs.remove(key);
    }

    // Clear dynamic water_history_* keys
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith('water_history_')) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> _handleUserSwitch(User? user) async {
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final lastUid = prefs.getString('last_uid');
    if (lastUid != null && lastUid != user.uid) {
      await _clearLocalUserData(prefs);
    }
    await prefs.setString('last_uid', user.uid);
  }

  /// ÄÄƒng xuáº¥t â€” giá»¯ cache local Ä‘á»ƒ user Ä‘Äƒng nháº­p láº¡i khÃ´ng máº¥t dá»¯ liá»‡u.
  /// Dá»¯ liá»‡u sáº½ Ä‘Æ°á»£c xÃ³a khi Ä‘Äƒng nháº­p báº±ng tÃ i khoáº£n khÃ¡c.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();

    // ÄÃ¡nh dáº¥u Ä‘Ã£ Ä‘Äƒng xuáº¥t â†’ khÃ´ng auto biometric login
    await prefs.setBool('just_logged_out', true);

    // Flush steps to Firestore before signing out (prevents loss when switching accounts)
    await _runWithTimeout(
      _flushHealthBeforeLogout(),
      timeout: _preLogoutSyncTimeout,
      label: 'preLogoutSync',
    );

    // Reset HealthService singleton Ä‘á»ƒ re-sync Firestore cho user má»›i
    HealthService().resetForLogout();

    await _runWithTimeout(
      _googleSignIn.signOut(),
      timeout: _googleSignOutTimeout,
      label: 'googleSignOut',
    );
    await _auth.signOut();
  }

  Future<void> _flushHealthBeforeLogout() async {
    await HealthService().saveTodayStepsToHistory();
    await HealthService().syncLocalStepsToFirestore();
  }

  // ==================== BIOMETRIC ====================

  /// Kiá»ƒm tra thiáº¿t bá»‹ cÃ³ há»— trá»£ sinh tráº¯c há»c khÃ´ng
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (e) {
      return false;
    }
  }

  /// Láº¥y danh sÃ¡ch loáº¡i sinh tráº¯c há»c cÃ³ sáºµn
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// XÃ¡c thá»±c báº±ng sinh tráº¯c há»c (Face ID / VÃ¢n tay / PIN)
  /// TrÃªn iPhone/Samsung/Pixel: quÃ©t máº·t/vÃ¢n tay trÆ°á»›c, PIN náº¿u fail
  /// TrÃªn Vivo/Oppo (face unlock riÃªng): hiá»‡n nháº­p PIN/pattern
  Future<bool> authenticateWithBiometric() async {
    try {
      final biometrics = await _localAuth.getAvailableBiometrics();
      final hasBiometric = biometrics.isNotEmpty;
      
      return await _localAuth.authenticate(
        localizedReason: hasBiometric 
            ? 'QuÃ©t khuÃ´n máº·t hoáº·c vÃ¢n tay Ä‘á»ƒ Ä‘Äƒng nháº­p BetterME'
            : 'Nháº­p mÃ£ PIN Ä‘á»ƒ Ä‘Äƒng nháº­p BetterME',
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: hasBiometric,
        ),
      );
    } catch (e) {
      // Fallback náº¿u biometricOnly gÃ¢y lá»—i
      try {
        return await _localAuth.authenticate(
          localizedReason: 'Nháº­p mÃ£ PIN Ä‘á»ƒ Ä‘Äƒng nháº­p BetterME',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
      } catch (_) {
        return false;
      }
    }
  }

  /// Báº­t/táº¯t Ä‘Äƒng nháº­p sinh tráº¯c há»c + Ä‘á»“ng bá»™ Firestore
  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', enabled);
    
    final firestoreService = FirestoreService();
    
    if (enabled && _auth.currentUser != null) {
      final user = _auth.currentUser!;
      await prefs.setString('biometric_uid', user.uid);
      
      // LÆ°u Ä‘Äƒng kÃ½ thiáº¿t bá»‹ lÃªn Firestore (banking-app style)
      String provider = 'password';
      for (final info in user.providerData) {
        if (info.providerId != 'firebase') {
          provider = info.providerId;
          break;
        }
      }
      await firestoreService.saveBiometricRegistration(
        email: user.email ?? '',
        provider: provider,
      );
      
      // LÆ°u credentials lÃªn Firestore Ä‘á»ƒ khÃ´i phá»¥c sau reinstall
      final biometricEmail = prefs.getString('biometric_saved_email') ?? prefs.getString('saved_email');
      final biometricPassword = prefs.getString('biometric_saved_password') ?? prefs.getString('saved_password');
      if (biometricEmail != null && biometricPassword != null) {
        await prefs.setString('biometric_saved_email', biometricEmail);
        await prefs.setString('biometric_saved_password', biometricPassword);
        await firestoreService.saveBiometricCredentials(
          email: biometricEmail,
          password: biometricPassword,
        );
      }
    } else {
      await prefs.remove('biometric_uid');
      await prefs.remove('biometric_saved_email');
      await prefs.remove('biometric_saved_password');
      // XÃ³a Ä‘Äƒng kÃ½ trÃªn Firestore
      await firestoreService.removeBiometricRegistration();
      await firestoreService.removeBiometricCredentials();
    }
  }

  /// Kiá»ƒm tra Ä‘Äƒng nháº­p sinh tráº¯c há»c Ä‘Ã£ báº­t chÆ°a (local + cloud fallback)
  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final localEnabled = prefs.getBool('biometric_enabled') ?? false;
    if (localEnabled) return true;
    
    // Fallback: kiá»ƒm tra Firestore náº¿u local data bá»‹ máº¥t (reinstall)
    if (_auth.currentUser != null) {
      final biometric = await FirestoreService().loadBiometricRegistration();
      if (biometric != null && biometric['enabled'] == true) {
        // KhÃ´i phá»¥c local settings tá»« Firestore
        await _restoreBiometricFromCloud();
        return true;
      }
    }
    return false;
  }

  /// Láº¥y email Ä‘Ã£ liÃªn káº¿t vá»›i sinh tráº¯c há»c
  Future<String?> getBiometricLinkedEmail() async {
    // Æ¯u tiÃªn kiá»ƒm tra local
    final prefs = await SharedPreferences.getInstance();
    final biometricUid = prefs.getString('biometric_uid');
    if (biometricUid != null && _auth.currentUser?.uid == biometricUid) {
      return _auth.currentUser?.email;
    }
    
    // Fallback: kiá»ƒm tra Firestore
    if (_auth.currentUser != null) {
      final biometric = await FirestoreService().loadBiometricRegistration();
      if (biometric != null) {
        return biometric['linkedEmail'] as String?;
      }
    }
    return null;
  }

  /// KhÃ´i phá»¥c biometric settings tá»« Firestore (sau reinstall)
  Future<bool> _restoreBiometricFromCloud() async {
    try {
      final firestoreService = FirestoreService();
      final biometric = await firestoreService.loadBiometricRegistration();
      if (biometric == null || biometric['enabled'] != true) return false;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_enabled', true);
      await prefs.setString('biometric_uid', _auth.currentUser!.uid);
      
      // KhÃ´i phá»¥c credentials tá»« Firestore
      final credentials = await firestoreService.loadBiometricCredentials();
      if (credentials != null) {
        await prefs.setString('biometric_saved_email', credentials['email']!);
        await prefs.setString('biometric_saved_password', credentials['password']!);
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// ÄÄƒng nháº­p báº±ng sinh tráº¯c há»c (dÃ¹ng láº¡i session Firebase trÆ°á»›c Ä‘Ã³)
  Future<AuthResult> loginWithBiometric() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var biometricUid = prefs.getString('biometric_uid');
      
      // Náº¿u local data bá»‹ máº¥t, thá»­ khÃ´i phá»¥c tá»« Firestore
      if (biometricUid == null && _auth.currentUser != null) {
        final restored = await _restoreBiometricFromCloud();
        if (restored) {
          biometricUid = prefs.getString('biometric_uid');
        }
      }
      
      // Kiá»ƒm tra cÃ³ tÃ i khoáº£n Ä‘Ã£ lÆ°u khÃ´ng
      if (biometricUid == null) {
        return AuthResult.failure(
          message: 'ChÆ°a thiáº¿t láº­p Ä‘Äƒng nháº­p sinh tráº¯c há»c.\nVÃ o CÃ i Ä‘áº·t â†’ Báº­t Face ID / VÃ¢n tay sau khi Ä‘Äƒng nháº­p.',
        );
      }
      
      // XÃ¡c thá»±c sinh tráº¯c há»c (Face/vÃ¢n tay/PIN)
      final authenticated = await authenticateWithBiometric();
      if (!authenticated) {
        return AuthResult.failure(message: 'XÃ¡c thá»±c sinh tráº¯c há»c tháº¥t báº¡i');
      }
      
      // Kiá»ƒm tra Firebase cÃ²n session khÃ´ng
      final currentUser = _auth.currentUser;
      if (currentUser != null && currentUser.uid == biometricUid) {
        _startPostLoginTasks();
        return AuthResult.success(user: currentUser);
      }
      
      // Náº¿u khÃ´ng cÃ²n session, dÃ¹ng biometric credentials (local)
      var savedEmail = prefs.getString('biometric_saved_email') ?? prefs.getString('saved_email');
      var savedPassword = prefs.getString('biometric_saved_password') ?? prefs.getString('saved_password');
      
      // Fallback: láº¥y credentials tá»« Firestore
      if (savedEmail == null || savedPassword == null) {
        final credentials = await FirestoreService().loadBiometricCredentials();
        if (credentials != null) {
          savedEmail = credentials['email'];
          savedPassword = credentials['password'];
          // LÆ°u láº¡i local cho biometric
          if (savedEmail != null) await prefs.setString('biometric_saved_email', savedEmail);
          if (savedPassword != null) await prefs.setString('biometric_saved_password', savedPassword);
        }
      }
      
      if (savedEmail != null && savedPassword != null) {
        return await loginWithEmail(email: savedEmail, password: savedPassword);
      }
      
      return AuthResult.failure(
        message: 'PhiÃªn Ä‘Äƒng nháº­p Ä‘Ã£ háº¿t háº¡n. Vui lÃ²ng Ä‘Äƒng nháº­p láº¡i báº±ng email.',
      );
    } catch (e) {
      return AuthResult.failure(message: 'Lá»—i Ä‘Äƒng nháº­p sinh tráº¯c há»c: $e');
    }
  }

  /// Kiá»ƒm tra user hiá»‡n táº¡i Ä‘Äƒng nháº­p báº±ng provider nÃ o
  String? get currentProvider {
    final user = _auth.currentUser;
    if (user == null) return null;
    for (final info in user.providerData) {
      if (info.providerId != 'firebase') {
        return info.providerId;
      }
    }
    return 'password';
  }

  /// Kiá»ƒm tra user cÃ³ pháº£i Email/Password khÃ´ng
  bool get isEmailPasswordUser {
    return currentProvider == 'password';
  }

  // ==================== HELPER ====================

  /// Chuyá»ƒn mÃ£ lá»—i Firebase thÃ nh tiáº¿ng Viá»‡t
  String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Email nÃ y Ä‘Ã£ Ä‘Æ°á»£c sá»­ dá»¥ng';
      case 'invalid-email':
        return 'Email khÃ´ng há»£p lá»‡';
      case 'operation-not-allowed':
        return 'PhÆ°Æ¡ng thá»©c Ä‘Äƒng nháº­p chÆ°a Ä‘Æ°á»£c báº­t';
      case 'weak-password':
        return 'Máº­t kháº©u quÃ¡ yáº¿u (cáº§n Ã­t nháº¥t 6 kÃ½ tá»±)';
      case 'user-disabled':
        return 'TÃ i khoáº£n Ä‘Ã£ bá»‹ vÃ´ hiá»‡u hÃ³a';
      case 'user-not-found':
        return 'KhÃ´ng tÃ¬m tháº¥y tÃ i khoáº£n vá»›i email nÃ y';
      case 'wrong-password':
        return 'Máº­t kháº©u khÃ´ng Ä‘Ãºng';
      case 'invalid-credential':
        return 'Email hoáº·c máº­t kháº©u khÃ´ng Ä‘Ãºng';
      case 'too-many-requests':
        return 'QuÃ¡ nhiá»u láº§n thá»­. Vui lÃ²ng Ä‘á»£i má»™t lÃ¡t';
      case 'network-request-failed':
        return 'Lá»—i káº¿t ná»‘i máº¡ng';
      default:
        return 'ÄÃ£ xáº£y ra lá»—i ($code)';
    }
  }
}

/// Káº¿t quáº£ xÃ¡c thá»±c
class AuthResult {
  final bool isSuccess;
  final User? user;
  final String? message;

  AuthResult._({
    required this.isSuccess,
    this.user,
    this.message,
  });

  factory AuthResult.success({User? user, String? message}) {
    return AuthResult._(isSuccess: true, user: user, message: message);
  }

  factory AuthResult.failure({required String message}) {
    return AuthResult._(isSuccess: false, message: message);
  }
}
