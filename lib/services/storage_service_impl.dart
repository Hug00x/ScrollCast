import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';
import '../main.dart';

// storage_service_impl.dart
//
// Propósito geral:
// - Implementação de `StorageService` que usa o sistema de ficheiros local
//   para guardar e organizar ficheiros específicos do utilizador.
// - Disponibiliza utilitários para obter diretórios do utilizador, criar
//   paths únicos para ficheiros (usando timestamp), e operações simples como
//   copiar, apagar e verificar existência de ficheiros.
//
// Organização do ficheiro:
// - Os métodos aqui assumem que o `ServiceLocator.instance.auth.currentUid`
//   fornece uma identificação do utilizador; quando não existe, usamos
//   um identificador '_anon' para separar ficheiros por utilizador.
// - A criação de diretórios usa `getApplicationDocumentsDirectory()` do
//   path_provider para armazenar dados por utilizador na sandbox da app.

//Implementação de StorageService que usa o sistema de ficheiros local.
class StorageServiceImpl implements StorageService {
  // Identificador do utilizador atual (fallback para '_anon').
  String get _uid => ServiceLocator.instance.auth.currentUid ?? '_anon';

  // Devolve o diretório raiz do utilizador atual (cria se não existir).
  // - Usa o application documents directory do dispositivo e anexa o uid
  //   para isolar ficheiros por utilizador.
  Future<Directory> _userRootDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final userDir = Directory(p.join(dir.path, _uid));
    if (!await userDir.exists()) await userDir.create(recursive: true);
    return userDir;
  }

  // Retorna o caminho para a raiz da app (pasta do utilizador).
  @override
  Future<String> appRoot() async => (await _userRootDir()).path;

  // Retorna o caminho para a pasta de áudio do utilizador, criando-a caso não exista.
  @override
  Future<String> audioDir() async {
    final root = await _userRootDir();
    final dir = Directory(p.join(root.path, 'audio'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  // Gera um caminho de ficheiro único dentro de `baseDir` usando timestamp.
  // Útil para criar ficheiros temporários ou novos ficheiros de gravação.
  @override
  Future<String> createUniqueFilePath(String baseDir, {required String extension}) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return p.join(baseDir, 'file_$ts.$extension');
  }

  // Copia um ficheiro de sourcePath para destPath.
  @override
  Future<void> copyFile(String sourcePath, String destPath) async {
    await File(sourcePath).copy(destPath);
  }

  // Apaga o ficheiro se existir.
  @override
  Future<void> deleteIfExists(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  // Verifica se um ficheiro existe (devolve uma Future<bool>).
  @override
  Future<bool> exists(String path) async => File(path).exists();
}
