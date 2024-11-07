import 'dart:convert';
import 'dart:typed_data';

class CapturedImage {
  final String? imgPath;
  final Uint8List? bytes;
  final bool didCaptureAutomatically;
  CapturedImage({
    this.imgPath,
    this.bytes,
    required this.didCaptureAutomatically,
  });

  CapturedImage copyWith({
    String? imgPath,
    Uint8List? bytes,
    bool? didCaptureAutomatically,
  }) {
    return CapturedImage(
      imgPath: imgPath ?? this.imgPath,
      bytes: bytes ?? this.bytes,
      didCaptureAutomatically:
          didCaptureAutomatically ?? this.didCaptureAutomatically,
    );
  }

  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{};

    result.addAll({'imgPath': imgPath});
    result.addAll({'bytes': bytes});
    result.addAll({'didCaptureAutomatically': didCaptureAutomatically});

    return result;
  }

  factory CapturedImage.fromMap(Map<String, dynamic> map) {
    return CapturedImage(
      imgPath: map['imgPath'] ?? '',
      bytes: map['bytes'],
      didCaptureAutomatically: map['didCaptureAutomatically'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory CapturedImage.fromJson(String source) =>
      CapturedImage.fromMap(json.decode(source));

  @override
  String toString() =>
      'CaptureImage(imgPath: $imgPath, didCaptureAutomatically: $didCaptureAutomatically, bytes: ${bytes?.length})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CapturedImage &&
        other.imgPath == imgPath &&
        other.bytes == bytes &&
        other.didCaptureAutomatically == didCaptureAutomatically;
  }

  @override
  int get hashCode => imgPath.hashCode ^ didCaptureAutomatically.hashCode;
}
