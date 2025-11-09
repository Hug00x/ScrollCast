import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage_service.dart';
import '../main.dart';

class StorageServiceImpl implements StorageService {
  String get _uid => ServiceLocator.instance.auth.currentUid ?? '_anon';

  Future<Directory> _userRootDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final userDir = Directory(p.join(dir.path, _uid));
    if (!await userDir.exists()) await userDir.create(recursive: true);
    return userDir;
  }

  @override
  Future<String> appRoot() async => (await _userRootDir()).path;


  @override
  Future<String> audioDir() async {
    final root = await _userRootDir();
    final dir = Directory(p.join(root.path, 'audio'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String> createUniqueFilePath(String baseDir, {required String extension}) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return p.join(baseDir, 'file_$ts.$extension');
  }

  @override
  Future<void> copyFile(String sourcePath, String destPath) async {
    await File(sourcePath).copy(destPath);
  }

  @override
  Future<void> deleteIfExists(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<bool> exists(String path) async => File(path).exists();
}
