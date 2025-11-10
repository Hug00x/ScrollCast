import 'dart:convert';
import 'dart:ui';

/*
  annotations.dart

  Propósito geral:
  - Define os tipos de anotações usados pelo editor: traços (strokes),
    notas de texto, notas de áudio e imagens inseridas.
  - Fornece serialização e desserialização para persistência (toMap/fromMap
    e toJson/fromJson) usada pelas camadas de armazenamento.

  Organização do ficheiro:
  - `StrokeMode` : enum com os modos suportados (pen, eraser).
  - `Stroke` : representa um traço desenhado, com pontos, largura, cor e modo.
  - `TextNote`, `AudioNote`, `ImageNote` : tipos auxiliares com respetivas
    funções copyWith e serialização.
  - `PageAnnotations` : agregador para todas as anotações de uma página,
    com helpers de serialização.

  Observações:
  - Anteriormente existia um modo "highlighter" (index 1), mas devido a problemas de desempenho, decidi removê-lo. O código atual
    filtra essas entradas ao desserializar `PageAnnotations` para evitar
    introduzir artefactos legados no editor.
*/

// Modo de traço: apenas caneta (pen) e borracha (eraser).
// Usamos enum simples para manter as opções claras ao serializar (index).
enum StrokeMode { pen, eraser }

// ----- Stroke -----
// Representa um traço feito pelo utilizador: uma sequência de pontos, largura, cor e modo (pen/eraser).
class Stroke {
  final List<Offset> points;
  final double width;
  final int color;
  final StrokeMode mode;

  const Stroke({
    required this.points,
    required this.width,
    required this.color,
    required this.mode,
  });

  // Serializa o Stroke para um Map simples.
  Map<String, dynamic> toMap() => {
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'width': width,
        'color': color,
        'mode': mode.index,
      };

  // Desserializa um Stroke a partir de Map.
  // Nota: Modos actuais (2 -> eraser, resto -> pen) (Anteriormente highlighter era 1).
  factory Stroke.fromMap(Map<String, dynamic> map) => Stroke(
        points: (map['points'] as List)
            .map((m) => Offset(
                  (m['x'] as num).toDouble(),
                  (m['y'] as num).toDouble(),
                ))
            .toList(),
        width: (map['width'] as num).toDouble(),
        color: map['color'] as int,
        mode: () {
          final mi = (map['mode'] as int?) ?? 0;
          if (mi == 2) return StrokeMode.eraser;
          return StrokeMode.pen;
        }(),
      );
}

class TextNote {
  final Offset position;
  final String text;

  const TextNote({required this.position, required this.text});

  // Serialização simples: posição + texto.
  Map<String, dynamic> toMap() =>
      {'x': position.dx, 'y': position.dy, 'text': text};

  // Desserialização de TextNote a partir de um Map.
  factory TextNote.fromMap(Map<String, dynamic> map) => TextNote(
        position: Offset(
          (map['x'] as num).toDouble(),
          (map['y'] as num).toDouble(),
        ),
        text: map['text'] as String,
      );
}

class AudioNote {
  final Offset position;
  final String filePath;
  final int durationMs;

  const AudioNote({
    required this.position,
    required this.filePath,
    required this.durationMs,
  });

  AudioNote copyWith({
    Offset? position,
    String? filePath,
    int? durationMs,
  }) {
    return AudioNote(
      position: position ?? this.position,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  // Serialização e desserialização para AudioNote.
  Map<String, dynamic> toMap() => {
        'x': position.dx,
        'y': position.dy,
        'filePath': filePath,
        'durationMs': durationMs,
      };

  factory AudioNote.fromMap(Map<String, dynamic> map) => AudioNote(
        position: Offset(
          (map['x'] as num).toDouble(),
          (map['y'] as num).toDouble(),
        ),
        filePath: (map['filePath'] ?? map['file']) as String,
        durationMs: (map['durationMs'] ?? map['dur']) as int,
      );
}

class ImageNote {
  final Offset position;
  final String filePath;
  final double width;
  final double height;
  final double rotation;

  const ImageNote({
    required this.position,
    required this.filePath,
    required this.width,
    required this.height,
    this.rotation = 0.0,
  });

  ImageNote copyWith({
    Offset? position,
    String? filePath,
    double? width,
    double? height,
    double? rotation,
  }) {
    return ImageNote(
      position: position ?? this.position,
      filePath: filePath ?? this.filePath,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
    );
  }

  // Serialização/deserialização de ImageNote (posição + ficheiro + dimensão).
  Map<String, dynamic> toMap() => {
        'x': position.dx,
        'y': position.dy,
        'filePath': filePath,
        'width': width,
        'height': height,
        'rotation': rotation,
      };

  factory ImageNote.fromMap(Map<String, dynamic> map) => ImageNote(
        position: Offset(
          (map['x'] as num).toDouble(),
          (map['y'] as num).toDouble(),
        ),
        filePath: map['filePath'] as String,
        width: (map['width'] as num).toDouble(),
        height: (map['height'] as num).toDouble(),
        rotation: (map['rotation'] as num?)?.toDouble() ?? 0.0,
      );
}

class PageAnnotations {
  final String pdfId;
  final int pageIndex;
  final List<Stroke> strokes;
  final List<TextNote> textNotes;
  final List<AudioNote> audioNotes;
  final List<ImageNote> imageNotes;

  const PageAnnotations({
    required this.pdfId,
    required this.pageIndex,
    this.strokes = const [],
    this.textNotes = const [],
    this.audioNotes = const [],
    this.imageNotes = const [],
  });

  PageAnnotations copyWith({
    List<Stroke>? strokes,
    List<TextNote>? textNotes,
    List<AudioNote>? audioNotes,
    List<ImageNote>? imageNotes,
  }) =>
      PageAnnotations(
        pdfId: pdfId,
        pageIndex: pageIndex,
        strokes: strokes ?? this.strokes,
        textNotes: textNotes ?? this.textNotes,
        audioNotes: audioNotes ?? this.audioNotes,
        imageNotes: imageNotes ?? this.imageNotes,
      );

  // Serialização completa da página: inclui todos os tipos de anotações.
  Map<String, dynamic> toMap() => {
        'pdfId': pdfId,
        'pageIndex': pageIndex,
        'strokes': strokes.map((e) => e.toMap()).toList(),
        'textNotes': textNotes.map((e) => e.toMap()).toList(),
        'audioNotes': audioNotes.map((e) => e.toMap()).toList(),
        'imageNotes': imageNotes.map((e) => e.toMap()).toList(),
      };

  // Desserialização: converte mapas para modelos. Importante:
  // - Filtramos explicitamente quaisquer strokes que venham do antigo modo
  //   "highlighter" (antigamente index 1)
  // - Para cada lista de notas usamos os helpers `fromMap` correspondentes.
  factory PageAnnotations.fromMap(Map<String, dynamic> map) => PageAnnotations(
        pdfId: map['pdfId'] as String,
        pageIndex: map['pageIndex'] as int,

        // Filtragem de strokes: descartamos entradas com mode==1 (legacy).
        strokes: (map['strokes'] as List)
            .map((m) => Map<String, dynamic>.from(m))
            .where((m) => (m['mode'] as int?) != 1)
            .map((m) => Stroke.fromMap(m))
            .toList(),

        textNotes: (map['textNotes'] as List)
            .map((m) => TextNote.fromMap(Map<String, dynamic>.from(m)))
            .toList(),
        audioNotes: (map['audioNotes'] as List)
            .map((m) => AudioNote.fromMap(Map<String, dynamic>.from(m)))
            .toList(),
        imageNotes: (map['imageNotes'] as List? ?? const [])
            .map((m) => ImageNote.fromMap(Map<String, dynamic>.from(m)))
            .toList(),
      );
  // Serialização para JSON
  String toJson() => json.encode(toMap());
  factory PageAnnotations.fromJson(String source) =>
      PageAnnotations.fromMap(json.decode(source) as Map<String, dynamic>);
}
