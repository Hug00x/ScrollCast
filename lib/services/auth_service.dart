abstract class AuthService {
  Stream<String?> authStateChanges(); // emite uid ou null
  String? get currentUid;

  Future<void> signInWithEmail(String email, String password);
  Future<void> signUpWithEmail(String email, String password);
  Future<void> signInWithGoogle();
  Future<void> signOut();
}
