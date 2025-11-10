//Interface abstrata para serviço de storage.
abstract class StorageService {
  //Retorna o diretório raiz da aplicação.
  Future<String> appRoot();

  // Retorna o diretório de áudio da aplicação.
  Future<String> audioDir();

  //Cria um caminho de ficheiro único.
  Future<String> createUniqueFilePath(String baseDir, {required String extension});

  //Copia um ficheiro de sourcePath para destPath.
  Future<void> copyFile(String sourcePath, String destPath);

  //Elimina o ficheiro no caminho especificado se existir.
  Future<void> deleteIfExists(String path);

  //Verifica se um ficheiro existe no caminho especificado.
  Future<bool> exists(String path);
}
