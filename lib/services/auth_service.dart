import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Authentication Service - Quản lý đăng nhập/đăng ký với Firebase
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Stream theo dõi trạng thái đăng nhập
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Người dùng hiện tại
  User? get currentUser => _auth.currentUser;

  /// Kiểm tra đã đăng nhập chưa
  bool get isLoggedIn => _auth.currentUser != null;

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
      return AuthResult.success(user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(message: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult.failure(message: 'Đã xảy ra lỗi: $e');
    }
  }

  // ==================== GOOGLE SIGN IN ====================

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

  // ==================== SIGN OUT ====================

  /// Đăng xuất
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
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
