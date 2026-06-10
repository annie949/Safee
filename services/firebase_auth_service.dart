import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  static bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  static Future<User?> signUpWithEmail(String email, String password, {String? username}) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      if (username != null && username.isNotEmpty) {
        await credential.user?.updateDisplayName(username);
      }

      // Don't send email here - let the signup screen handle it
      return credential.user;
    } on FirebaseAuthException catch (e) {
      throw e;
    }
  }

  static Future<User?> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      return credential.user;
    } on FirebaseAuthException catch (e) {
      throw e;
    }
  }

  static Future<void> sendVerificationEmail() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  static Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  static Future<void> deleteAccount() async {
    await _auth.currentUser?.delete();
  }
}