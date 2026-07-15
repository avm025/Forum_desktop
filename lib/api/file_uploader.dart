import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../services/api_logger.dart';
import '../utils/file_kind.dart';
import '../utils/image_dimensions.dart';
import 'api_config.dart';
import 'client_msg_hash.dart';
import 'uploaded_file_info.dart';

/// HTTP multipart upload (WS_MSG_MEDIA.md, UploadMessage.swift).
class FileUploader {
  FileUploader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<UploadedFileInfo> upload({
    required Uint8List bytes,
    required Map<String, dynamic> metadataBody,
  }) =>
      _uploadMultipart(bytes: bytes, metadataBody: metadataBody);

  Future<UploadedFileInfo> _uploadMultipart({
    required Uint8List bytes,
    required Map<String, dynamic> metadataBody,
  }) async {
    final fileHash = ClientMsgHash.generate();
    final kind = metadataBody['kind']?.toString() ?? 'bin';
    final fname = metadataBody['fname']?.toString() ?? '$fileHash.$kind';

    final meta = Map<String, dynamic>.from(metadataBody)
      ..['kind'] = kind
      ..['size'] = bytes.length
      ..['fname'] = fname;

    final bodyJson = jsonEncode(meta);
    final uri = ApiConfig.uploadServerUri;

    // UploadMessage.swift: boundary = file hash; fields hash, body, key; file as octet-stream.
    final bodyBytes = _buildMultipartBody(
      boundary: fileHash,
      fields: {
        'hash': fileHash,
        'body': bodyJson,
        'key': ApiConfig.apiKey,
      },
      fileBytes: bytes,
    );

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer ${ApiConfig.token}'
      ..headers['Key'] = ApiConfig.apiKey
      ..headers['Cache-Control'] = 'no-cache'
      ..headers['Content-Type'] = 'multipart/form-data; boundary=$fileHash'
      ..bodyBytes = bodyBytes;

    ApiLogger.instance.logHttpSend(
      'POST',
      uri.toString(),
      {
        'hash': fileHash,
        'body': meta,
        'key': ApiConfig.apiKey,
        'file': 'file (${bytes.length} bytes)',
      },
    );

    final sw = Stopwatch()..start();
    final streamed = await _client.send(request).timeout(const Duration(seconds: 120));
    final responseBody = await streamed.stream.bytesToString().timeout(
          const Duration(seconds: 120),
        );
    sw.stop();

    ApiLogger.instance.logHttpReceive(
      streamed.statusCode,
      responseBody,
      duration: sw.elapsed,
    );

    if (streamed.statusCode == 401) {
      throw FileUploadException('401: $responseBody');
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw FileUploadException('HTTP ${streamed.statusCode}: $responseBody');
    }

    final map = Map<String, dynamic>.from(jsonDecode(responseBody) as Map);
    if (map['success'] == false) {
      throw FileUploadException(
        map['message']?.toString() ?? 'Ошибка загрузки файла',
        payload: map,
      );
    }

    final data = map['data'];
    if (data is Map) {
      return UploadedFileInfo.fromJson(Map<String, dynamic>.from(data));
    }

    return UploadedFileInfo.fromJson(map);
  }

  /// Multipart body как в UploadMessage.swift.
  static Uint8List _buildMultipartBody({
    required String boundary,
    required Map<String, String> fields,
    required Uint8List fileBytes,
  }) {
    final chunks = <int>[];

    void write(String s) => chunks.addAll(utf8.encode(s));

    for (final entry in fields.entries) {
      write('--$boundary\r\n');
      write('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n');
      write('${entry.value}\r\n');
    }

    write('--$boundary\r\n');
    write('Content-Disposition: form-data; name=file; filename=file\r\n');
    write('Content-Type: application/octet-stream\r\n\r\n');
    chunks.addAll(fileBytes);
    write('\r\n--$boundary--\r\n');

    return Uint8List.fromList(chunks);
  }

  Future<UploadedFileInfo> uploadMedia({
    required Uint8List bytes,
    required String originalName,
    int duration = 0,
  }) async {
    final kind = FileKind.mediaKindFromName(originalName);

    final metadata = <String, dynamic>{
      'kind': kind,
      'size': bytes.length,
    };
    if (FileKind.isVideoKind(kind) && duration > 0) {
      metadata['duration'] = duration;
    }

    return upload(bytes: bytes, metadataBody: metadata);
  }

  Future<UploadedFileInfo> uploadDocument({
    required Uint8List bytes,
    required String originalName,
  }) async {
    final kind = FileKind.kindFromName(originalName);

    return upload(
      bytes: bytes,
      metadataBody: {
        'kind': kind,
        'title': originalName,
        'size': bytes.length,
      },
    );
  }
}

class FileUploadException implements Exception {
  final String message;
  final Map<String, dynamic>? payload;

  FileUploadException(this.message, {this.payload});

  @override
  String toString() => message;
}

/// Размеры и WS body для media после upload.
class MediaUploadResult {
  final UploadedFileInfo file;
  final String width;
  final String height;

  const MediaUploadResult({
    required this.file,
    this.width = '',
    this.height = '',
  });

  Map<String, String> toMediaBodyEntry({String duration = '0', String preview = ''}) {
    return file.toMediaFileJson(
      width: width,
      height: height,
      duration: duration,
      preview: preview,
    );
  }
}

extension FileUploaderMedia on FileUploader {
  Future<MediaUploadResult> uploadMediaWithDimensions({
    required Uint8List bytes,
    required String originalName,
    int duration = 0,
    String width = '',
    String height = '',
  }) async {
    final dims = (width.isEmpty || height.isEmpty) ? readImageDimensions(bytes) : null;
    final uploaded = await uploadMedia(
      bytes: bytes,
      originalName: originalName,
      duration: duration,
    );
    return MediaUploadResult(
      file: uploaded,
      width: width.isNotEmpty ? width : (dims?.widthStr ?? ''),
      height: height.isNotEmpty ? height : (dims?.heightStr ?? ''),
    );
  }
}
