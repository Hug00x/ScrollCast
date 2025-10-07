abstract class AuthService {
  Stream<String?> authStateChanges();
  Future<void> signInWithEmail(String email, String pass);
  Future<void> signUpWithEmail(String email, String pass);
  Future<void> signInWithGoogle();
  Future<void> signOut();
  String? get currentUid;
}
