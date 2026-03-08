import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_service.dart';

/// Authentication Service - Quản lý đăng nhập/đăng ký với Firebase
class AuthService {
  /// Kiểm tra Firebase đã được khởi tạo chưa
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

  /// Stream theo dõi trạng thái đăng nhập
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Người dùng hiện tại
  User? get currentUser => _isFirebaseReady ? _auth.currentUser : null;

  /// Kiểm tra đã đăng nhập chưa
  bool get isLoggedIn => _isFirebaseReady && _auth.currentUser != null;

  // ==================== EMAIL/PASSWORD ====================

  /// Đăng ký bằng email và mật khẩu
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

      // Cập nhật tên hiển thị nếu có
      if (displayName != null && credential.user != null) {
        await credential.user!.updateDisplayName(displayName);
        await credential.user!.reload();
      }

      await _saveUserMetaToFirestore();
      return AuthResult.success(user: _auth.currentUser);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'Đã xảy ra lỗi: $e');
    }
  }

  /// Đăng nhập bằng email và mật khẩu
  Future<AuthResult> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _saveUserMetaToFirestore();
      return AuthResult.success(user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'Đã xảy ra lỗi: $e');
    }
  }

  /// Lưu thông tin user vào Firestore sau khi đăng nhập thành công
  Future<void> _saveUserMetaToFirestore() async {
    try {
      await FirestoreService().saveUserMeta();
    } catch (e) {
      // Không block login nếu Firestore lỗi
    }
  }

  // ==================== GOOGLE SIGN IN ======================================

  /// Đăng nhập bằng Google
  Future<AuthResult> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return AuthResult.failure(message: 'Đăng nhập Google bị hủy');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _saveUserMetaToFirestore();
      return AuthResult.success(user: userCredential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'Lỗi đăng nhập Google: $e');
    }
  }

  // ==================== APPLE SIGN IN ====================

  /// Đăng nhập bằng Apple
  Future<AuthResult> signInWithApple() async {
    try {
      final appleProvider = AppleAuthProvider();
      appleProvider.addScope('email');
      appleProvider.addScope('name');

      final userCredential = await _auth.signInWithProvider(appleProvider);
      await _saveUserMetaToFirestore();
      return AuthResult.success(user: userCredential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'Lỗi đăng nhập Apple: $e');
    }
  }

  // ==================== FORGOT PASSWORD ====================

  /// Gửi email đặt lại mật khẩu
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return AuthResult.success(
        message: 'Email đặt lại mật khẩu đã được gửi đến $email',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'Đã xảy ra lỗi: $e');
    }
  }

  // ==================== CHANGE PASSWORD ====================

  /// Đổi mật khẩu
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Chưa đăng nhập');
    }
    
    if (user.email == null) {
      throw Exception('Tài khoản không có email (đăng nhập bằng Google/Apple)');
    }
    
    // Re-authenticate với mật khẩu hiện tại
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw Exception('Mật khẩu hiện tại không đúng');
      }
      throw Exception(_getErrorMessage(e.code));
    }
    
    // Đổi mật khẩu
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_getErrorMessage(e.code));
    }
  }

  // ==================== SIGN OUT ====================

  /// Đăng xuất
  Future<void> signOut() async {
    // Đánh dấu đã đăng xuất thủ công → không auto biometric login
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('just_logged_out', true);
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // ==================== BIOMETRIC ====================

  /// Kiểm tra thiết bị có hỗ trợ sinh trắc học không
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (e) {
      return false;
    }
  }

  /// Lấy danh sách loại sinh trắc học có sẵn
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Xác thực bằng sinh trắc học (Face ID / Vân tay / PIN)
  /// Trên iPhone/Samsung/Pixel: quét mặt/vân tay trước, PIN nếu fail
  /// Trên Vivo/Oppo (face unlock riêng): hiện nhập PIN/pattern
  Future<bool> authenticateWithBiometric() async {
    try {
      final biometrics = await _localAuth.getAvailableBiometrics();
      final hasBiometric = biometrics.isNotEmpty;
      
      return await _localAuth.authenticate(
        localizedReason: hasBiometric 
            ? 'Quét khuôn mặt hoặc vân tay để đăng nhập BetterME'
            : 'Nhập mã PIN để đăng nhập BetterME',
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: hasBiometric,
        ),
      );
    } catch (e) {
      // Fallback nếu biometricOnly gây lỗi
      try {
        return await _localAuth.authenticate(
          localizedReason: 'Nhập mã PIN để đăng nhập BetterME',
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

  /// Bật/tắt đăng nhập sinh trắc học + đồng bộ Firestore
  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', enabled);
    
    final firestoreService = FirestoreService();
    
    if (enabled && _auth.currentUser != null) {
      final user = _auth.currentUser!;
      await prefs.setString('biometric_uid', user.uid);
      
      // Lưu đăng ký thiết bị lên Firestore (banking-app style)
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
      
      // Lưu credentials lên Firestore để khôi phục sau reinstall
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
      // Xóa đăng ký trên Firestore
      await firestoreService.removeBiometricRegistration();
      await firestoreService.removeBiometricCredentials();
    }
  }

  /// Kiểm tra đăng nhập sinh trắc học đã bật chưa (local + cloud fallback)
  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final localEnabled = prefs.getBool('biometric_enabled') ?? false;
    if (localEnabled) return true;
    
    // Fallback: kiểm tra Firestore nếu local data bị mất (reinstall)
    if (_auth.currentUser != null) {
      final biometric = await FirestoreService().loadBiometricRegistration();
      if (biometric != null && biometric['enabled'] == true) {
        // Khôi phục local settings từ Firestore
        await _restoreBiometricFromCloud();
        return true;
      }
    }
    return false;
  }

  /// Lấy email đã liên kết với sinh trắc học
  Future<String?> getBiometricLinkedEmail() async {
    // Ưu tiên kiểm tra local
    final prefs = await SharedPreferences.getInstance();
    final biometricUid = prefs.getString('biometric_uid');
    if (biometricUid != null && _auth.currentUser?.uid == biometricUid) {
      return _auth.currentUser?.email;
    }
    
    // Fallback: kiểm tra Firestore
    if (_auth.currentUser != null) {
      final biometric = await FirestoreService().loadBiometricRegistration();
      if (biometric != null) {
        return biometric['linkedEmail'] as String?;
      }
    }
    return null;
  }

  /// Khôi phục biometric settings từ Firestore (sau reinstall)
  Future<bool> _restoreBiometricFromCloud() async {
    try {
      final firestoreService = FirestoreService();
      final biometric = await firestoreService.loadBiometricRegistration();
      if (biometric == null || biometric['enabled'] != true) return false;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_enabled', true);
      await prefs.setString('biometric_uid', _auth.currentUser!.uid);
      
      // Khôi phục credentials từ Firestore
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

  /// Đăng nhập bằng sinh trắc học (dùng lại session Firebase trước đó)
  Future<AuthResult> loginWithBiometric() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var biometricUid = prefs.getString('biometric_uid');
      
      // Nếu local data bị mất, thử khôi phục từ Firestore
      if (biometricUid == null && _auth.currentUser != null) {
        final restored = await _restoreBiometricFromCloud();
        if (restored) {
          biometricUid = prefs.getString('biometric_uid');
        }
      }
      
      // Kiểm tra có tài khoản đã lưu không
      if (biometricUid == null) {
        return AuthResult.failure(
          message: 'Chưa thiết lập đăng nhập sinh trắc học.\nVào Cài đặt → Bật Face ID / Vân tay sau khi đăng nhập.',
        );
      }
      
      // Xác thực sinh trắc học (Face/vân tay/PIN)
      final authenticated = await authenticateWithBiometric();
      if (!authenticated) {
        return AuthResult.failure(message: 'Xác thực sinh trắc học thất bại');
      }
      
      // Kiểm tra Firebase còn session không
      final currentUser = _auth.currentUser;
      if (currentUser != null && currentUser.uid == biometricUid) {
        await _saveUserMetaToFirestore();
        return AuthResult.success(user: currentUser);
      }
      
      // Nếu không còn session, dùng biometric credentials (local)
      var savedEmail = prefs.getString('biometric_saved_email') ?? prefs.getString('saved_email');
      var savedPassword = prefs.getString('biometric_saved_password') ?? prefs.getString('saved_password');
      
      // Fallback: lấy credentials từ Firestore
      if (savedEmail == null || savedPassword == null) {
        final credentials = await FirestoreService().loadBiometricCredentials();
        if (credentials != null) {
          savedEmail = credentials['email'];
          savedPassword = credentials['password'];
          // Lưu lại local cho biometric
          if (savedEmail != null) await prefs.setString('biometric_saved_email', savedEmail);
          if (savedPassword != null) await prefs.setString('biometric_saved_password', savedPassword);
        }
      }
      
      if (savedEmail != null && savedPassword != null) {
        return await loginWithEmail(email: savedEmail, password: savedPassword);
      }
      
      return AuthResult.failure(
        message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại bằng email.',
      );
    } catch (e) {
      return AuthResult.failure(message: 'Lỗi đăng nhập sinh trắc học: $e');
    }
  }

  /// Kiểm tra user hiện tại đăng nhập bằng provider nào
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

  /// Kiểm tra user có phải Email/Password không
  bool get isEmailPasswordUser {
    return currentProvider == 'password';
  }

  // ==================== HELPER ====================

  /// Chuyển mã lỗi Firebase thành tiếng Việt
  String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Email này đã được sử dụng';
      case 'invalid-email':
        return 'Email không hợp lệ';
      case 'operation-not-allowed':
        return 'Phương thức đăng nhập chưa được bật';
      case 'weak-password':
        return 'Mật khẩu quá yếu (cần ít nhất 6 ký tự)';
      case 'user-disabled':
        return 'Tài khoản đã bị vô hiệu hóa';
      case 'user-not-found':
        return 'Không tìm thấy tài khoản với email này';
      case 'wrong-password':
        return 'Mật khẩu không đúng';
      case 'invalid-credential':
        return 'Email hoặc mật khẩu không đúng';
      case 'too-many-requests':
        return 'Quá nhiều lần thử. Vui lòng đợi một lát';
      case 'network-request-failed':
        return 'Lỗi kết nối mạng';
      default:
        return 'Đã xảy ra lỗi ($code)';
    }
  }
}

/// Kết quả xác thực
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
