import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = 'Session expired. Please login again.']);
  @override
  String toString() => message;
}

class ApiService {
  static const String _defaultBaseUrl = '';

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('server_url') ?? _defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    var normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isNotEmpty &&
        !normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    await prefs.setString('server_url', normalized);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_data');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map['username']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
    await prefs.remove('device_id');
  }

  // Login & Device Handshake
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required String deviceName,
    required String deviceType,
  }) async {
    final baseUrl = await getBaseUrl();
    if (baseUrl.isEmpty) {
      throw Exception('Please enter a valid Server Address');
    }
    final url = Uri.parse('$baseUrl/api/v1/auth/login');

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'password': password,
            'deviceUid': 'mobile-$deviceName-${DateTime.now().millisecondsSinceEpoch}',
            'deviceName': deviceName,
            'deviceType': deviceType,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', data['token']);
      await prefs.setString('user_data', jsonEncode(data['user']));
      await prefs.setString('device_id', data['device']['id']);
      return data;
    } else {
      throw Exception(data['error'] ?? 'Login failed');
    }
  }

  // Fetch all user files from DG Cloud
  static Future<List<Map<String, dynamic>>> getFiles({String? deviceId}) async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    if (baseUrl.isEmpty || token == null) {
      throw UnauthorizedException();
    }

    final uri = deviceId != null
        ? Uri.parse('$baseUrl/api/v1/files?deviceId=$deviceId')
        : Uri.parse('$baseUrl/api/v1/files');

    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to load files (HTTP ${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['files'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Fetch Cloud Storage Quota & Volumes
  static Future<Map<String, dynamic>> getStorageStatus() async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    if (baseUrl.isEmpty || token == null) {
      throw UnauthorizedException();
    }

    final response = await http
        .get(
          Uri.parse('$baseUrl/api/v1/storage/status'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to load storage status');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // Fetch Connected Devices
  static Future<List<Map<String, dynamic>>> getDevices() async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    if (baseUrl.isEmpty || token == null) {
      throw UnauthorizedException();
    }

    final response = await http
        .get(
          Uri.parse('$baseUrl/api/v1/devices'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to load devices');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['devices'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Build authenticated Stream URL for Image/Media viewing
  static Future<String?> getFileStreamUrl(String fileId) async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    if (baseUrl.isEmpty || token == null) return null;
    return '$baseUrl/api/v1/files/$fileId/stream?token=$token';
  }

  // Download decrypted file directly to local device storage
  static Future<String> downloadFile({
    required String fileId,
    required String fileName,
    Function(double progress)? onProgress,
  }) async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    if (baseUrl.isEmpty || token == null) {
      throw UnauthorizedException();
    }

    final url = Uri.parse('$baseUrl/api/v1/files/$fileId/stream?token=$token');
    final request = http.Request('GET', url);
    final client = http.Client();

    try {
      final response = await client.send(request);
      if (response.statusCode == 401) {
        throw UnauthorizedException();
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Download failed (HTTP ${response.statusCode})');
      }

      Directory targetDir;
      if (Platform.isAndroid) {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) {
          targetDir = publicDownload;
        } else {
          targetDir = (await getExternalStorageDirectory()) ??
              await getApplicationDocumentsDirectory();
        }
      } else {
        targetDir = await getApplicationDocumentsDirectory();
      }

      var savePath = '${targetDir.path}/$fileName';
      File outFile = File(savePath);

      // Avoid writing failure on Android scoped restrictions by falling back cleanly
      try {
        await outFile.create(recursive: true);
      } catch (_) {
        final fallbackDir = await getApplicationDocumentsDirectory();
        savePath = '${fallbackDir.path}/$fileName';
        outFile = File(savePath);
      }

      final sink = outFile.openWrite();
      final totalBytes = response.contentLength ?? 0;
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(received / totalBytes);
        }
      }

      await sink.flush();
      await sink.close();
      return savePath;
    } finally {
      client.close();
    }
  }

  // Calculate SHA-256 Checksum of a local file on phone
  static Future<String> computeFileChecksum(File file) async {
    final stream = file.openRead();
    final hash = await sha256.bind(stream).first;
    return hash.toString();
  }

  // Pre-flight check for instant zero-bandwidth deduplication
  static Future<Map<String, dynamic>> preflightCheck(
      String checksum, String fileName) async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();

    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/files/preflight'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'sha256Checksum': checksum,
        'fileName': fileName,
      }),
    );

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // Chunked Upload for ANY file from phone (Photos, Videos, PDFs, ZIPs, Docs)
  static Future<void> uploadFile({
    required File file,
    required String fileName,
    bool isCloudPinned = false,
    Function(double progress, String status)? onProgress,
  }) async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    final fileSize = await file.length();

    onProgress?.call(0.05, 'Checking file checksum...');
    final checksum = await computeFileChecksum(file);

    // 1. Instant Deduplication check
    onProgress?.call(0.1, 'Checking duplicate status on server...');
    final preflight = await preflightCheck(checksum, fileName);
    if (preflight['isDuplicate'] == true) {
      onProgress?.call(1.0, 'Instant Deduplication: File already present!');
      return;
    }

    // 2. Init Upload Session
    const chunkSize = 5 * 1024 * 1024; // 5 MB Chunks
    final totalChunks = fileSize == 0 ? 1 : (fileSize / chunkSize).ceil();

    final initRes = await http.post(
      Uri.parse('$baseUrl/api/v1/files/upload/init'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'fileName': fileName,
        'fileSize': fileSize,
        'totalChunks': totalChunks,
        'expectedChecksum': checksum,
        'isCloudPinned': isCloudPinned,
      }),
    );

    if (initRes.statusCode != 201) {
      throw Exception('Failed to initialize upload session');
    }

    final session = jsonDecode(initRes.body) as Map<String, dynamic>;
    final sessionId = session['sessionId'];

    // 3. Upload Chunks
    final randomAccessFile = await file.open(mode: FileMode.read);
    for (int chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
      final start = chunkIndex * chunkSize;
      final remaining = fileSize - start;
      final bytesToRead = remaining < chunkSize ? remaining : chunkSize;

      await randomAccessFile.setPosition(start);
      final chunkBytes = bytesToRead > 0
          ? await randomAccessFile.read(bytesToRead)
          : <int>[];

      final chunkRes = await http.post(
        Uri.parse(
            '$baseUrl/api/v1/files/upload/chunk?sessionId=$sessionId&chunkIndex=$chunkIndex'),
        headers: {
          'Content-Type': 'application/octet-stream',
          'Authorization': 'Bearer $token',
        },
        body: chunkBytes,
      );

      if (chunkRes.statusCode != 200) {
        await randomAccessFile.close();
        throw Exception('Failed to upload chunk $chunkIndex');
      }

      final progress = ((chunkIndex + 1) / totalChunks);
      onProgress?.call(progress, 'Uploading: ${(progress * 100).toInt()}%');
    }
    await randomAccessFile.close();

    // 4. Finalize & Complete Upload
    onProgress?.call(0.95, 'Encrypting & verifying on server...');
    final completeRes = await http.post(
      Uri.parse('$baseUrl/api/v1/files/upload/complete'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'sessionId': sessionId}),
    );

    if (completeRes.statusCode != 200) {
      throw Exception('Failed to finalize file upload');
    }

    onProgress?.call(1.0, 'Upload verified & encrypted!');
  }
}
