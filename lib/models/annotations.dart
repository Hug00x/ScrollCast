import 'dart:convert';
import 'dart:ui';

enum StrokeMode { pen, highlighter, eraser }

class Stroke {
  final List<Offset> points;
  final double width;
  final int color; // ARGB
  final StrokeMode mode;

  const Stroke({
    required this.points,
    required this.width,
    required this.color,
    required this.mode,
  });

  Map<String, dynamic> toMap() => {
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'width': width,
        'color': color,
        'mode': mode.index,
      };

  factory Stroke.fromMap(Map<String, dynamic> map) => Stroke(
        points: (map['points'] as List)
            .map((m) => Offset(
                  (m['x'] as num).toDouble(),
                  (m['y'] as num).toDouble(),
                ))
            .toList(),
        width: (map['width'] as num).toDouble(),
        color: map['color'] as int,
        mode: StrokeMode.values[map['mode'] as int],
      );
}

class TextNote {
  final Offset position;
  final String text;
  final String? label;

  const TextNote({required this.position, required this.text, this.label});

  TextNote copyWith({Offset? position, String? text, String? label}) {
    return TextNote(
      position: position ?? this.position,
      text: text ?? this.text,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toMap() =>
      {'x': position.dx, 'y': position.dy, 'text': text, 'label': label};

  factory TextNote.fromMap(Map<String, dynamic> map) => TextNote(
        position: Offset(
          (map['x'] as num).toDouble(),
          (map['y'] as num).toDouble(),
        ),
        text: map['text'] as String,
        label: (map['label'] as String?)?.isEmpty ?? true ? null : (map['label'] as String?),
      );
}

class AudioNote {
  final Offset position;
  final String filePath;
  final int durationMs;
  final String? label;

  const AudioNote({
    required this.position,
    required this.filePath,
    required this.durationMs,
    this.label,
  });

  AudioNote copyWith({
    Offset? position,
    String? filePath,
    int? durationMs,
    String? label,
  }) {
    return AudioNote(
      position: position ?? this.position,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toMap() => {
        'x': position.dx,
        'y': position.dy,
        'filePath': filePath,
        'durationMs': durationMs,
    'label': label,
      };

  /// Aceita chaves antigas ('file', 'dur') para compatibilidade.
  factory AudioNote.fromMap(Map<String, dynamic> map) => AudioNote(
        position: Offset(
          (map['x'] as num).toDouble(),
          (map['y'] as num).toDouble(),
        ),
        filePath: (map['filePath'] ?? map['file']) as String,
        durationMs: (map['durationMs'] ?? map['dur']) as int,
        label: (map['label'] as String?)?.isEmpty ?? true ? null : (map['label'] as String?),
      );
}

class ImageNote {
  final Offset position;
  final String filePath;
  final double width;
  final double height;
  final double rotation; // radians

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

  Map<String, dynamic> toMap() => {
        'pdfId': pdfId,
        'pageIndex': pageIndex,
        'strokes': strokes.map((e) => e.toMap()).toList(),
        'textNotes': textNotes.map((e) => e.toMap()).toList(),
        'audioNotes': audioNotes.map((e) => e.toMap()).toList(),
    'imageNotes': imageNotes.map((e) => e.toMap()).toList(),
      };

  factory PageAnnotations.fromMap(Map<String, dynamic> map) => PageAnnotations(
        pdfId: map['pdfId'] as String,
        pageIndex: map['pageIndex'] as int,
        strokes: (map['strokes'] as List)
            .map((m) => Stroke.fromMap(Map<String, dynamic>.from(m)))
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

  String toJson() => json.encode(toMap());
  factory PageAnnotations.fromJson(String source) =>
      PageAnnotations.fromMap(json.decode(source) as Map<String, dynamic>);
}
