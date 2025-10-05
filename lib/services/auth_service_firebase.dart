import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

class AuthServiceFirebase implements AuthService {
  final _auth = FirebaseAuth.instance;

  @override
  Stream<String?> authStateChanges() => _auth.authStateChanges().map((u) => u?.uid);

  @override
  String? get currentUid => _auth.currentUser?.uid;

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signUpWithEmail(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signInWithGoogle() async {
    final googleUser = await GoogleSignIn(scopes: ['email']).signIn();
    if (googleUser == null) return; // cancelado
    final gAuth = await googleUser.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );
    await _auth.signInWithCredential(cred);
  }

  @override
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }
}
