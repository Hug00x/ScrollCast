abstract class StorageService {
  Future<String> appRoot();

  Future<String> audioDir();
  Future<String> createUniqueFilePath(String baseDir, {required String extension});
  Future<void> copyFile(String sourcePath, String destPath);
  Future<void> deleteIfExists(String path);
  Future<bool> exists(String path);
}
