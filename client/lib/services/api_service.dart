import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
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

  static String normalizeServerUrl(String url) {
    var normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isNotEmpty &&
        !normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    return normalized;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', normalizeServerUrl(url));
  }

  static Future<Map<String, dynamic>> _authRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final baseUrl = await getBaseUrl();
    final token = await getToken();
    if (baseUrl.isEmpty || token == null) {
      throw UnauthorizedException();
    }

    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Authorization': 'Bearer $token'};
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    final encodedBody = body != null ? jsonEncode(body) : null;
    late final http.Response response;
    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(uri, headers: headers).timeout(timeout);
        break;
      case 'POST':
        response = await http
            .post(uri, headers: headers, body: encodedBody)
            .timeout(timeout);
        break;
      case 'PATCH':
        response = await http
            .patch(uri, headers: headers, body: encodedBody)
            .timeout(timeout);
        break;
      case 'PUT':
        response = await http
            .put(uri, headers: headers, body: encodedBody)
            .timeout(timeout);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers).timeout(timeout);
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }

    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }

    final parsed = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(parsed['error'] ?? 'Request failed (HTTP ${response.statusCode})');
    }
    return parsed;
  }

  static Future<Map<String, dynamic>> _publicPost(
    String path,
    Map<String, dynamic> body, {
    String? serverUrl,
  }) async {
    final rawBase = serverUrl != null && serverUrl.trim().isNotEmpty
        ? normalizeServerUrl(serverUrl)
        : await getBaseUrl();
    if (rawBase.isEmpty) {
      throw Exception('Please enter a valid Server Address');
    }

    final response = await http
        .post(
          Uri.parse('$rawBase$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    final parsed = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(parsed['error'] ?? 'Request failed (HTTP ${response.statusCode})');
    }
    return parsed;
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

  static const Map<String, String> _appleMachineMap = {
    'iPhone13,1': 'iPhone 12 mini',
    'iPhone13,2': 'iPhone 12',
    'iPhone13,3': 'iPhone 12 Pro',
    'iPhone13,4': 'iPhone 12 Pro Max',
    'iPhone14,2': 'iPhone 13 Pro',
    'iPhone14,3': 'iPhone 13 Pro Max',
    'iPhone14,4': 'iPhone 13 mini',
    'iPhone14,5': 'iPhone 13',
    'iPhone14,6': 'iPhone SE (3rd gen)',
    'iPhone14,7': 'iPhone 14',
    'iPhone14,8': 'iPhone 14 Plus',
    'iPhone15,2': 'iPhone 14 Pro',
    'iPhone15,3': 'iPhone 14 Pro Max',
    'iPhone15,4': 'iPhone 15',
    'iPhone15,5': 'iPhone 15 Plus',
    'iPhone16,1': 'iPhone 15 Pro',
    'iPhone16,2': 'iPhone 15 Pro Max',
    'iPhone17,1': 'iPhone 16 Pro',
    'iPhone17,2': 'iPhone 16 Pro Max',
    'iPhone17,3': 'iPhone 16',
    'iPhone17,4': 'iPhone 16 Plus',
    'iPhone17,5': 'iPhone 16e',
  };

  /// Returns a stable unique device ID persisted across logouts & app restarts.
  static Future<String> getOrCreateDeviceUid(String deviceType) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('persistent_device_uid');
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final rng = Random.secure();
    final hex = List<String>.generate(
      12,
      (_) => rng.nextInt(16).toRadixString(16),
    ).join();
    final uid = 'app-$deviceType-$hex';
    await prefs.setString('persistent_device_uid', uid);
    return uid;
  }

  /// Auto-detects hardware model name and platform cleanly on Android & iOS.
  static Future<Map<String, String>> detectDeviceInfo() async {
    final deviceType = Platform.isAndroid
        ? 'android'
        : (Platform.isIOS ? 'ios' : Platform.operatingSystem);
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final brandRaw = info.brand.trim();
        final model = info.model.trim();
        final brand = brandRaw.isNotEmpty
            ? '${brandRaw[0].toUpperCase()}${brandRaw.substring(1)}'
            : '';
        String name;
        if (model.isNotEmpty &&
            brand.isNotEmpty &&
            !model.toLowerCase().startsWith(brand.toLowerCase())) {
          name = '$brand $model';
        } else if (model.isNotEmpty) {
          name = model;
        } else if (brand.isNotEmpty) {
          name = '$brand Phone';
        } else {
          name = 'Android Phone';
        }
        return {'deviceName': name, 'deviceType': 'android'};
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final machine = info.utsname.machine.trim();
        final friendly = _appleMachineMap[machine] ??
            (info.model.trim().isNotEmpty ? info.model.trim() : 'iPhone');
        return {'deviceName': friendly, 'deviceType': 'ios'};
      }
    } catch (_) {}

    final host = Platform.localHostname.replaceAll('.local', '').trim();
    return {
      'deviceName': host.isNotEmpty
          ? host
          : (Platform.isAndroid ? 'Android Phone' : 'iPhone'),
      'deviceType': deviceType,
    };
  }

  // Login & Device Handshake
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? deviceName,
    String? deviceType,
  }) async {
    final baseUrl = await getBaseUrl();
    if (baseUrl.isEmpty) {
      throw Exception('Please enter a valid Server Address');
    }
    final detected = await detectDeviceInfo();
    final effectiveType = (deviceType != null && deviceType.trim().isNotEmpty)
        ? deviceType.trim()
        : detected['deviceType']!;
    final effectiveName = (deviceName != null && deviceName.trim().isNotEmpty)
        ? deviceName.trim()
        : detected['deviceName']!;
    final deviceUid = await getOrCreateDeviceUid(effectiveType);
    final url = Uri.parse('$baseUrl/api/v1/auth/login');

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'password': password,
            'deviceUid': deviceUid,
            'deviceName': effectiveName,
            'deviceType': effectiveType,
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
    final path = deviceId != null ? '/api/v1/files?deviceId=$deviceId' : '/api/v1/files';
    final data = await _authRequest('GET', path);
    final list = data['files'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Delete a file (moves to Recycle Bin)
  static Future<Map<String, dynamic>> deleteFile(String fileId, {bool purge = false}) async {
    final query = purge ? '?purge=1' : '';
    return _authRequest('DELETE', '/api/v1/files/$fileId$query');
  }

  // Fetch Recycle Bin (Trash) files
  static Future<List<Map<String, dynamic>>> getTrash() async {
    final data = await _authRequest('GET', '/api/v1/trash');
    final list = data['trash'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Restore file from Recycle Bin
  static Future<Map<String, dynamic>> restoreTrashFile(String fileId) async {
    return _authRequest('POST', '/api/v1/trash/$fileId/restore');
  }

  // Permanently purge file from Recycle Bin
  static Future<Map<String, dynamic>> purgeTrashFile(String fileId) async {
    return _authRequest('DELETE', '/api/v1/trash/$fileId/purge');
  }

  // Permanently empty entire Recycle Bin
  static Future<Map<String, dynamic>> emptyTrash() async {
    return _authRequest('DELETE', '/api/v1/trash');
  }

  // Create Encrypted Public Share Link
  static Future<Map<String, dynamic>> createShareLink({
    required String fileId,
    String? password,
    int? expiresInDays,
    int? expiresHours,
  }) async {
    final computedHours = expiresHours ?? (expiresInDays != null && expiresInDays > 0 ? expiresInDays * 24 : 72);
    final body = <String, dynamic>{
      'fileId': fileId,
    };
    if (password != null && password.isNotEmpty) body['password'] = password;
    body['expiresHours'] = computedHours;

    return _authRequest('POST', '/api/v1/shares', body: body);
  }

  // List active user shares
  static Future<List<Map<String, dynamic>>> getShares() async {
    final data = await _authRequest('GET', '/api/v1/shares');
    final list = data['shares'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Revoke share link
  static Future<Map<String, dynamic>> revokeShare(String shareId) async {
    return _authRequest('DELETE', '/api/v1/shares/$shareId');
  }

  // Rename a file in cloud vault
  static Future<Map<String, dynamic>> renameFile(String fileId, String newFileName) async {
    return _authRequest('PATCH', '/api/v1/files/$fileId', body: {'fileName': newFileName});
  }

  // Fetch Cloud Storage Quota & Volumes
  static Future<Map<String, dynamic>> getStorageStatus() async {
    return _authRequest('GET', '/api/v1/storage/status');
  }

  // Mount new local storage drive / volume
  static Future<Map<String, dynamic>> addStorageVolume({
    required String volumeName,
    required String mountPath,
    String volumeType = 'local_hdd',
    bool autoScan = true,
  }) async {
    return _authRequest(
      'POST',
      '/api/v1/storage/volumes',
      body: {
        'volumeName': volumeName,
        'mountPath': mountPath,
        'volumeType': volumeType,
        'autoScan': autoScan,
      },
    );
  }

  // Update existing storage volume
  static Future<Map<String, dynamic>> updateStorageVolume({
    required String volumeId,
    String? volumeName,
    String? mountPath,
    String? volumeType,
  }) async {
    final body = <String, dynamic>{};
    if (volumeName != null && volumeName.isNotEmpty) body['volumeName'] = volumeName;
    if (mountPath != null && mountPath.isNotEmpty) body['mountPath'] = mountPath;
    if (volumeType != null && volumeType.isNotEmpty) body['volumeType'] = volumeType;

    return _authRequest('PUT', '/api/v1/storage/volumes/$volumeId', body: body);
  }

  // Remove / Unmount storage volume
  static Future<Map<String, dynamic>> removeStorageVolume(String volumeId, {bool purgeFiles = true}) async {
    final query = purgeFiles ? '?purge_files=1' : '';
    return _authRequest('DELETE', '/api/v1/storage/volumes/$volumeId$query');
  }

  // Scan & index files on storage volume
  static Future<Map<String, dynamic>> scanStorageVolume(String volumeId) async {
    return _authRequest('POST', '/api/v1/storage/volumes/$volumeId/scan');
  }

  // Run Storage Cleaner & Duplicate Scanner
  static Future<Map<String, dynamic>> scanDuplicates({String? targetPath}) async {
    return _authRequest(
      'POST',
      '/api/v1/cleaner/scan',
      body: targetPath != null && targetPath.isNotEmpty ? {'targetPath': targetPath} : {},
      timeout: const Duration(seconds: 60),
    );
  }

  // Fetch Security & Recovery Configuration Status
  static Future<Map<String, dynamic>> getSecurityStatus() async {
    return _authRequest('GET', '/api/v1/auth/security/status');
  }

  // Change password for authenticated account
  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _authRequest(
      'POST',
      '/api/v1/auth/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  // Begin 2FA Authenticator Setup
  static Future<Map<String, dynamic>> setupTotp() async {
    return _authRequest('POST', '/api/v1/auth/totp/setup');
  }

  // Verify 6-digit code and link 2FA Authenticator to Encryption Vault
  static Future<Map<String, dynamic>> enableTotp({
    required String secret,
    required String code,
    required String password,
  }) async {
    return _authRequest(
      'POST',
      '/api/v1/auth/totp/enable',
      body: {'secret': secret, 'code': code, 'password': password},
    );
  }

  // Configure & Test Telegram Bot Recovery & Security Alerts
  static Future<Map<String, dynamic>> setupTelegram({
    required String botToken,
    required String chatId,
    required String currentPassword,
    bool alertsEnabled = true,
  }) async {
    return _authRequest(
      'POST',
      '/api/v1/auth/telegram/setup',
      body: {
        'botToken': botToken,
        'chatId': chatId,
        'currentPassword': currentPassword,
        'alertsEnabled': alertsEnabled,
      },
    );
  }

  // Unlink Telegram Recovery & Alerts
  static Future<Map<String, dynamic>> unlinkTelegram() async {
    return _authRequest('POST', '/api/v1/auth/telegram/unlink');
  }

  // Account Recovery: Emergency Recovery Key
  static Future<Map<String, dynamic>> recoverWithKey({
    String? serverUrl,
    required String username,
    required String recoveryKey,
    required String newPassword,
  }) async {
    return _publicPost(
      '/api/v1/auth/recover',
      {
        'username': username,
        'recoveryKey': recoveryKey,
        'newPassword': newPassword,
      },
      serverUrl: serverUrl,
    );
  }

  // Account Recovery: 2FA Authenticator Secret + 6-Digit Code
  static Future<Map<String, dynamic>> recoverWithTotp({
    String? serverUrl,
    required String username,
    required String totpSecret,
    required String code,
    required String newPassword,
  }) async {
    return _publicPost(
      '/api/v1/auth/totp/recover',
      {
        'username': username,
        'totpSecret': totpSecret,
        'code': code,
        'newPassword': newPassword,
      },
      serverUrl: serverUrl,
    );
  }

  // Account Recovery: Request 6-digit OTP via Telegram Bot
  static Future<Map<String, dynamic>> requestTelegramReset({
    String? serverUrl,
    required String username,
  }) async {
    return _publicPost(
      '/api/v1/auth/telegram/request-reset',
      {'username': username},
      serverUrl: serverUrl,
    );
  }

  // Account Recovery: Confirm Telegram OTP and set new password
  static Future<Map<String, dynamic>> resetWithTelegramOtp({
    String? serverUrl,
    required String username,
    required String otpCode,
    required String newPassword,
  }) async {
    return _publicPost(
      '/api/v1/auth/telegram/reset',
      {
        'username': username,
        'otpCode': otpCode,
        'newPassword': newPassword,
      },
      serverUrl: serverUrl,
    );
  }

  // Fetch Connected Devices
  static Future<List<Map<String, dynamic>>> getDevices() async {
    final data = await _authRequest('GET', '/api/v1/devices');
    final list = data['devices'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Syncs the real detected device name and cleans stale 0-file duplicates.
  static Future<void> syncDeviceInfo() async {
    final info = await detectDeviceInfo();
    await _authRequest(
      'POST',
      '/api/v1/devices/sync-info',
      body: {
        'deviceName': info['deviceName'],
        'deviceType': info['deviceType'],
      },
    );
  }

  /// Removes an old device entry while preserving its uploaded files in the vault.
  static Future<Map<String, dynamic>> deleteDevice(String deviceId) async {
    return _authRequest('DELETE', '/api/v1/devices/${Uri.encodeComponent(deviceId)}');
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
