import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'services/sync_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SyncEngine.initialize();
  runApp(const DGCloudApp());
}

class DGCloudApp extends StatelessWidget {
  const DGCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DG Cloud',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          onPrimary: Colors.white,
          secondary: Color(0xFF10B981),
          onSecondary: Colors.white,
          surface: Color(0xFF172036),
          onSurface: Color(0xFFF3F4F6),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF1E3A8A),
            disabledForegroundColor: Colors.white70,
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF172036),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0x14FFFFFF)),
          ),
          elevation: 0,
        ),
      ),
      home: const MainGateScreen(),
    );
  }
}

// =============================================================================
// FORMATTING HELPERS
// =============================================================================
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(i == 0 ? 0 : 2)} ${suffixes[i]}';
}

String formatDateDDMMYYYY(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$dd-$mm-$yyyy $hh:$min:$ss';
  } catch (_) {
    return iso;
  }
}

String detectCategory(String fileName, String? mimeType) {
  final lower = fileName.toLowerCase();
  final mime = (mimeType ?? '').toLowerCase();

  if (mime.startsWith('image/') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic')) {
    return 'Photos';
  }
  if (mime.startsWith('video/') ||
      lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.webm')) {
    return 'Videos';
  }
  if (mime.startsWith('application/pdf') ||
      mime.startsWith('text/') ||
      lower.endsWith('.pdf') ||
      lower.endsWith('.doc') ||
      lower.endsWith('.docx') ||
      lower.endsWith('.txt') ||
      lower.endsWith('.xls') ||
      lower.endsWith('.xlsx') ||
      lower.endsWith('.ppt') ||
      lower.endsWith('.csv')) {
    return 'Docs';
  }
  if (lower.endsWith('.zip') ||
      lower.endsWith('.rar') ||
      lower.endsWith('.7z') ||
      lower.endsWith('.tar') ||
      lower.endsWith('.gz')) {
    return 'Archives';
  }
  return 'Other';
}

IconData categoryIcon(String category) {
  switch (category) {
    case 'Photos':
      return Icons.image_rounded;
    case 'Videos':
      return Icons.videocam_rounded;
    case 'Docs':
      return Icons.description_rounded;
    case 'Archives':
      return Icons.archive_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

Color categoryColor(String category) {
  switch (category) {
    case 'Photos':
      return const Color(0xFF10B981);
    case 'Videos':
      return const Color(0xFF8B5CF6);
    case 'Docs':
      return const Color(0xFFF59E0B);
    case 'Archives':
      return const Color(0xFFEC4899);
    default:
      return const Color(0xFF3B82F6);
  }
}

// =============================================================================
// AUTHENTICATION GATE
// =============================================================================
class MainGateScreen extends StatefulWidget {
  const MainGateScreen({super.key});

  @override
  State<MainGateScreen> createState() => _MainGateScreenState();
}

class _MainGateScreenState extends State<MainGateScreen> {
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final token = await ApiService.getToken();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = token != null && token.isNotEmpty;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _isLoggedIn ? const DashboardScreen() : const LoginScreen();
  }
}

// =============================================================================
// LOGIN SCREEN
// =============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedUrl() async {
    final savedUrl = await ApiService.getBaseUrl();
    if (savedUrl.isNotEmpty && mounted) {
      setState(() {
        _serverUrlController.text = savedUrl;
      });
    }
  }

  Future<void> _handleLogin() async {
    final serverUrl = _serverUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (serverUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Server Address (e.g. http://...)')),
      );
      return;
    }
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username and Password are required')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiService.setBaseUrl(serverUrl);
      await ApiService.login(
        username: username,
        password: password,
        deviceName: Platform.isAndroid ? 'Android-Phone' : 'iPhone',
        deviceType: Platform.isAndroid ? 'android' : 'ios',
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text(
              'Login Error: ${e.toString().replaceAll('Exception: ', '')}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withAlpha(70),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/app_icon.png',
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 92,
                        height: 92,
                        padding: const EdgeInsets.all(18),
                        color: const Color(0xFF172036),
                        child: const Icon(
                          Icons.cloud_done_rounded,
                          size: 54,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'DG Cloud Drive',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Private Encrypted Cloud Storage & Auto-Sync',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _serverUrlController,
                          keyboardType: TextInputType.url,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Server Address',
                            hintText: 'http://your-server-ip',
                            prefixIcon: const Icon(Icons.dns_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: const Icon(Icons.person_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _isSubmitting ? null : _handleLogin,
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.login_rounded, color: Colors.white),
                            label: Text(
                              _isSubmitting ? 'Connecting...' : 'Sign In to DG Cloud',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: const Color(0xFF172036),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(22),
                                      ),
                                    ),
                                    builder: (_) => _ForgotPasswordSheet(
                                      initialServerUrl: _serverUrlController.text.trim(),
                                      initialUsername: _usernameController.text.trim(),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.lock_reset_rounded, size: 18),
                          label: const Text('Forgot Password? Recover Account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// MAIN DASHBOARD WITH BOTTOM NAVIGATION (DRIVE STYLE)
// =============================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTab = 0;

  // Cloud Files & Storage state
  bool _isLoadingFiles = true;
  String? _loadError;
  List<Map<String, dynamic>> _allFiles = [];
  List<Map<String, dynamic>> _devices = [];
  Map<String, dynamic>? _storageStatus;
  Map<String, dynamic>? _securityStatus;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String? _selectedDeviceId;
  String? _selectedDeviceName;
  String _baseUrl = '';
  String _token = '';
  String _username = 'Owner';

  // Upload state
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';

  // Auto-sync state
  List<String> _syncFolders = [];

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  Future<void> _initDashboard() async {
    final url = await ApiService.getBaseUrl();
    final tok = await ApiService.getToken();
    final uname = await ApiService.getUsername();
    final folders = await SyncEngine.getSyncFolders();

    if (!mounted) return;
    setState(() {
      _baseUrl = url;
      _token = tok ?? '';
      _username = uname ?? 'Owner';
      _syncFolders = folders;
    });

    await _refreshAllData();
  }

  Future<void> _refreshAllData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingFiles = true;
      _loadError = null;
    });

    try {
      final filesFuture = ApiService.getFiles();
      final statusFuture = ApiService.getStorageStatus();
      final devicesFuture = ApiService.getDevices();
      final securityFuture = ApiService.getSecurityStatus()
          .then<Map<String, dynamic>?>((v) => v)
          .catchError((_) => null);

      final files = await filesFuture;
      final status = await statusFuture;
      final devices = await devicesFuture;
      final security = await securityFuture;

      if (!mounted) return;
      setState(() {
        _allFiles = files;
        _storageStatus = status;
        _devices = devices;
        _securityStatus = security;
        _isLoadingFiles = false;
      });
    } on UnauthorizedException {
      await ApiService.logout();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingFiles = false;
        _loadError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> get _filteredFiles {
    return _allFiles.where((f) {
      final name = (f['file_name'] ?? '').toString();
      final mime = (f['mime_type'] ?? '').toString();
      final devId = (f['device_id'] ?? '').toString();
      final matchesSearch = _searchQuery.isEmpty ||
          name.toLowerCase().contains(_searchQuery.toLowerCase());
      final category = detectCategory(name, mime);
      final matchesCat =
          _selectedCategory == 'All' || category == _selectedCategory;
      final matchesDevice = _selectedDeviceId == null || devId == _selectedDeviceId;
      return matchesSearch && matchesCat && matchesDevice;
    }).toList();
  }

  Future<void> _pickAndUploadAnyFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadStatus = 'Preparing upload...';
    });

    final files = result.files;
    int successCount = 0;

    for (int i = 0; i < files.length; i++) {
      final f = files[i];
      if (f.path == null) continue;

      if (mounted) {
        setState(() {
          _uploadStatus = 'Uploading [${i + 1}/${files.length}]: ${f.name}';
        });
      }

      try {
        await ApiService.uploadFile(
          file: File(f.path!),
          fileName: f.name,
          onProgress: (p, status) {
            if (mounted) {
              setState(() {
                _uploadProgress = p;
                _uploadStatus = '[${i + 1}/${files.length}] $status';
              });
            }
          },
        );
        successCount++;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFEF4444),
              content: Text(
                'Upload failed for ${f.name}: $e',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _uploadStatus = '';
    });

    if (successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text(
            'Successfully uploaded $successCount file(s) to DG Cloud!',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      );
      await _refreshAllData();
    }
  }

  Future<void> _downloadCloudFile(Map<String, dynamic> file) async {
    final fileId = file['id'].toString();
    final fileName = file['file_name'].toString();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading $fileName...')),
    );

    try {
      final savedPath = await ApiService.downloadFile(
        fileId: fileId,
        fileName: fileName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 4),
          content: Text(
            'Saved to: $savedPath',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text(
            'Download error: $e',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  Future<void> _renameCloudFile(Map<String, dynamic> file) async {
    final currentName = (file['file_name'] ?? '').toString();
    final ctrl = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF172036),
        title: const Text('Rename File', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'New File Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (newName == null || newName.isEmpty || newName == currentName) return;

    try {
      await ApiService.renameFile(file['id'].toString(), newName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Renamed to $newName'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      await _refreshAllData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<bool> _deleteCloudFile(Map<String, dynamic> file) async {
    final name = (file['file_name'] ?? 'this file').toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF172036),
        title: const Text('Delete File?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to permanently delete "$name"?',
          style: const TextStyle(color: Color(0xFFD1D5DB)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return false;

    try {
      await ApiService.deleteFile(file['id'].toString());
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted "$name"'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      await _refreshAllData();
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return false;
    }
  }

  void _openFilePreviewOrSheet(Map<String, dynamic> file) {
    final name = (file['file_name'] ?? '').toString();
    final mime = (file['mime_type'] ?? '').toString();
    final category = detectCategory(name, mime);
    final fileId = file['id'].toString();

    if (category == 'Photos' && _baseUrl.isNotEmpty && _token.isNotEmpty) {
      final imageUrl = '$_baseUrl/api/v1/files/$fileId/stream?token=$_token';
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (viewerCtx) => PhotoViewerScreen(
            fileName: name,
            imageUrl: imageUrl,
            onDownload: () => _downloadCloudFile(file),
            onDelete: () async {
              final deleted = await _deleteCloudFile(file);
              if (deleted && viewerCtx.mounted) {
                Navigator.of(viewerCtx).pop();
              }
            },
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF172036),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sizeBytes = (file['file_size'] as num?)?.toInt() ?? 0;
        final deviceName = (file['device_name'] ?? 'Web').toString();
        final createdAt = formatDateDDMMYYYY(file['created_at']?.toString());
        final lifecycle = (file['lifecycle_status'] ?? 'CLOUD_BUFFER').toString();

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: categoryColor(category).withAlpha(40),
                    child: Icon(
                      categoryIcon(category),
                      color: categoryColor(category),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0x1FFFFFFF)),
              const SizedBox(height: 8),
              _DetailRow(label: 'Size', value: formatBytes(sizeBytes)),
              _DetailRow(label: 'Category', value: category),
              _DetailRow(label: 'Uploaded From', value: deviceName),
              _DetailRow(label: 'Storage Location', value: lifecycle),
              _DetailRow(label: 'Uploaded At', value: createdAt),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                label: const Text(
                  'Download to Phone',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _downloadCloudFile(file);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Rename'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _renameCloudFile(file);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Delete'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _deleteCloudFile(file);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addSyncFolder() async {
    final selectedDir = await FilePicker.platform.getDirectoryPath();
    if (selectedDir != null) {
      await SyncEngine.addSyncFolder(selectedDir);
      final folders = await SyncEngine.getSyncFolders();
      if (!mounted) return;
      setState(() => _syncFolders = folders);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text(
            'Added to auto-sync: $selectedDir',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  Future<void> _removeSyncFolder(String path) async {
    await SyncEngine.removeSyncFolder(path);
    final folders = await SyncEngine.getSyncFolders();
    if (!mounted) return;
    setState(() => _syncFolders = folders);
  }

  void _showServerDialog() {
    final controller = TextEditingController(text: _baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF172036),
        title: const Text('Server Address', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Cloud Server URL',
            hintText: 'http://your-server-ip',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await ApiService.setBaseUrl(newUrl);
                final updated = await ApiService.getBaseUrl();
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (!mounted) return;
                setState(() => _baseUrl = updated);
                _refreshAllData();
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['DG Cloud Drive', 'Auto-Sync Folders', 'Storage & Account'];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                'assets/app_icon.png',
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.cloud_done_rounded,
                  color: Color(0xFF3B82F6),
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              titles[_selectedTab],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refreshAllData,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildFilesTab(),
          _buildAutoSyncTab(),
          _buildStorageTab(),
        ],
      ),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              onPressed: _isUploading ? null : _pickAndUploadAnyFiles,
              icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
              label: const Text(
                'Upload File',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0F172A),
        indicatorColor: const Color(0xFF3B82F6).withAlpha(60),
        selectedIndex: _selectedTab,
        onDestinationSelected: (idx) {
          setState(() => _selectedTab = idx);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded, color: Color(0xFF3B82F6)),
            label: 'My Files',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_outlined),
            selectedIcon: Icon(Icons.sync_rounded, color: Color(0xFF10B981)),
            label: 'Auto-Sync',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart_rounded, color: Color(0xFF3B82F6)),
            label: 'Storage',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 0: MY FILES (GOOGLE DRIVE STYLE EXPLORER)
  // ===========================================================================
  Widget _buildFilesTab() {
    final userStats = _storageStatus?['userStats'] as Map<String, dynamic>?;
    final totalBytes = (userStats?['total_user_bytes'] as num?)?.toInt() ?? 0;
    final quotaBytes = (_storageStatus?['cloudQuotaBytes'] as num?)?.toInt() ?? 161061273600;
    final usedRatio = quotaBytes > 0 ? (totalBytes / quotaBytes).clamp(0.0, 1.0) : 0.0;
    final files = _filteredFiles;

    const categories = ['All', 'Photos', 'Videos', 'Docs', 'Archives', 'Other'];

    return RefreshIndicator(
      onRefresh: _refreshAllData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          // Live Upload Progress Banner
          if (_isUploading) ...[
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _uploadStatus,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _uploadProgress,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Compact Storage Meter Banner
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Cloud Vault (${_allFiles.length} Files)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${formatBytes(totalBytes)} / ${formatBytes(quotaBytes)}',
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usedRatio,
                      minHeight: 6,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Search Box
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search files in your cloud...',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9CA3AF)),
              filled: true,
              fillColor: const Color(0xFF172036),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Active Device Filter Chip
          if (_selectedDeviceId != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withAlpha(35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3B82F6).withAlpha(110)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.smartphone_rounded, size: 18, color: Color(0xFF60A5FA)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Device filter: ${_selectedDeviceName ?? "Selected Device"}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedDeviceId = null;
                        _selectedDeviceName = null;
                      });
                    },
                    child: const Text('Show All'),
                  ),
                ],
              ),
            ),
          ],

          // Category Filter Chips
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final cat = categories[i];
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(
                    cat,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF3B82F6),
                  backgroundColor: const Color(0xFF172036),
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Files Body
          if (_isLoadingFiles)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loadError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 42, color: Color(0xFFEF4444)),
                    const SizedBox(height: 8),
                    Text(
                      'Could not load files:\n$_loadError',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('Retry', style: TextStyle(color: Colors.white)),
                      onPressed: _refreshAllData,
                    ),
                  ],
                ),
              ),
            )
          else if (files.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_queue_rounded, size: 54, color: Color(0xFF3B82F6)),
                    const SizedBox(height: 12),
                    const Text(
                      'No Files Found',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tap "Upload File" below to safely back up your photos, videos, PDFs, or ZIP files.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
                      label: const Text(
                        'Browse & Upload File',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isUploading ? null : _pickAndUploadAnyFiles,
                    ),
                  ],
                ),
              ),
            )
          else
            ...files.map((file) => _buildFileTile(file)),
        ],
      ),
    );
  }

  Widget _buildFileTile(Map<String, dynamic> file) {
    final id = file['id'].toString();
    final name = (file['file_name'] ?? 'Unnamed').toString();
    final mime = (file['mime_type'] ?? '').toString();
    final sizeBytes = (file['file_size'] as num?)?.toInt() ?? 0;
    final deviceName = (file['device_name'] ?? 'Web').toString();
    final dateStr = formatDateDDMMYYYY(file['created_at']?.toString()).split(' ').first;
    final cat = detectCategory(name, mime);
    final isPhoto = cat == 'Photos' && _baseUrl.isNotEmpty && _token.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onTap: () => _openFilePreviewOrSheet(file),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 48,
            height: 48,
            child: isPhoto
                ? Image.network(
                    '$_baseUrl/api/v1/files/$id/stream?token=$_token',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _IconBadge(cat: cat),
                  )
                : _IconBadge(cat: cat),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${formatBytes(sizeBytes)}  •  $dateStr  •  $deviceName',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded, color: Color(0xFF3B82F6)),
              tooltip: 'Download',
              onPressed: () => _downloadCloudFile(file),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF9CA3AF)),
              color: const Color(0xFF1E293B),
              onSelected: (action) {
                if (action == 'download') _downloadCloudFile(file);
                if (action == 'rename') _renameCloudFile(file);
                if (action == 'delete') _deleteCloudFile(file);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.download_rounded, size: 18, color: Color(0xFF60A5FA)),
                      SizedBox(width: 8),
                      Text('Download'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_rounded, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Rename'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: AUTO-SYNC FOLDERS
  // ===========================================================================
  Widget _buildAutoSyncTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.sync_rounded, color: Color(0xFF10B981), size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Silent Background Auto-Sync',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Files placed inside these phone folders will automatically back up to your private cloud every 15 minutes when internet is available.',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
                        label: const Text(
                          'Add Folder',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _addSyncFolder,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.sync_rounded, color: Colors.white),
                        label: const Text(
                          'Sync Now',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Running background folder sync...')),
                          );
                          await SyncEngine.runBackgroundSync();
                          await _refreshAllData();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF10B981),
                              content: Text(
                                'Folder sync cycle complete!',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Watched Phone Folders',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        if (_syncFolders.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No folders selected yet. Tap "Add Folder" above to choose Camera, WhatsApp, or Downloads.',
                style: TextStyle(color: Color(0xFF9CA3AF)),
              ),
            ),
          )
        else
          ..._syncFolders.map(
            (path) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.folder_special_rounded, color: Color(0xFF10B981)),
                title: Text(path, style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text(
                  'Auto-backup enabled',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                  onPressed: () => _removeSyncFolder(path),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // TAB 2: STORAGE, SECURITY, DEVICES & ACCOUNT SETTINGS
  // ===========================================================================
  void _openModalSheet(Widget sheet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF172036),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => sheet,
    );
  }

  Widget _buildStorageTab() {
    final userStats = _storageStatus?['userStats'] as Map<String, dynamic>?;
    final totalBytes = (userStats?['total_user_bytes'] as num?)?.toInt() ?? 0;
    final totalFiles = (userStats?['total_files'] as num?)?.toInt() ?? _allFiles.length;
    final quotaBytes = (_storageStatus?['cloudQuotaBytes'] as num?)?.toInt() ?? 161061273600;
    final usedPercent = quotaBytes > 0 ? ((totalBytes / quotaBytes) * 100).clamp(0.0, 100.0) : 0.0;
    final volumes = (_storageStatus?['volumes'] as List<dynamic>? ?? [])
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();

    final totpEnabled = _securityStatus?['totpEnabled'] == true;
    final tgMap = _securityStatus?['telegram'] as Map<String, dynamic>?;
    final tgLinked = tgMap?['linked'] == true;
    final tgMaskedChat = tgMap?['maskedChatId']?.toString();

    return RefreshIndicator(
      onRefresh: _refreshAllData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          // Profile Hero Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/app_icon.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFF3B82F6).withAlpha(40),
                            child: const Icon(Icons.person_rounded, color: Color(0xFF3B82F6)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _username,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'AES-256-GCM Encrypted Private Vault',
                              style: TextStyle(color: Color(0xFF10B981), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _StatusPill(
                        label: totpEnabled ? '🔐 2FA Active' : '🔐 2FA Not Setup',
                        isActive: totpEnabled,
                      ),
                      _StatusPill(
                        label: tgLinked ? '✈️ Telegram Linked' : '✈️ Telegram Not Linked',
                        isActive: tgLinked,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${formatBytes(totalBytes)} used (${usedPercent.toStringAsFixed(1)}%)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$totalFiles Files',
                        style: const TextStyle(color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: quotaBytes > 0 ? (totalBytes / quotaBytes).clamp(0.0, 1.0) : 0,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Total Cloud Allocation: ${formatBytes(quotaBytes)}',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Security & Account Tools (Web Parity)
          const Text(
            'Security & Storage Tools',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded, color: Color(0xFFF59E0B)),
                  title: const Text(
                    '🧹 Storage Cleaner & Duplicates',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Scan drives & ZIPs to find duplicate files',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
                  onTap: () => _openModalSheet(const _CleanerModalSheet()),
                ),
                const Divider(height: 1, color: Color(0x14FFFFFF)),
                ListTile(
                  leading: Icon(
                    Icons.security_rounded,
                    color: totpEnabled ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                  ),
                  title: const Text(
                    '🔐 2FA Security (Authenticator App)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    totpEnabled
                        ? 'Active (Google / Microsoft Authenticator)'
                        : 'Tap to activate fail-safe 2FA backup',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
                  onTap: () => _openModalSheet(
                    _TotpSetupSheet(
                      isAlreadyEnabled: totpEnabled,
                      onActivated: _refreshAllData,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0x14FFFFFF)),
                ListTile(
                  leading: const Icon(Icons.key_rounded, color: Color(0xFF60A5FA)),
                  title: const Text(
                    '🔑 Change Account Password',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Re-encrypt vault safely with a new password',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
                  onTap: () => _openModalSheet(const _ChangePasswordSheet()),
                ),
                const Divider(height: 1, color: Color(0x14FFFFFF)),
                ListTile(
                  leading: Icon(
                    Icons.send_rounded,
                    color: tgLinked ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                  ),
                  title: const Text(
                    '✈️ Telegram Recovery & Alerts',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    tgLinked
                        ? 'Linked ($tgMaskedChat) • Instant OTP reset'
                        : 'Link personal Telegram Bot for OTP reset & alerts',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
                  onTap: () => _openModalSheet(
                    _TelegramSetupSheet(
                      isLinked: tgLinked,
                      maskedChatId: tgMaskedChat,
                      onUpdated: _refreshAllData,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // My Devices Section (Tap device to browse its files)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Devices',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                'Tap device to browse',
                style: TextStyle(color: Colors.blue.shade300, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_devices.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No devices found.', style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            )
          else
            ..._devices.map(
              (d) {
                final dName = (d['device_name'] ?? 'Unknown Device').toString();
                final dType = (d['device_type'] ?? 'mobile').toString();
                final isSelected = _selectedDeviceId == d['id']?.toString();
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF10B981).withAlpha(35),
                      child: Icon(
                        dType == 'web' || dType == 'windows'
                            ? Icons.computer_rounded
                            : Icons.smartphone_rounded,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                    title: Text(
                      dName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${d['total_files_count'] ?? 0} files  •  ${formatBytes((d['total_used_bytes'] as num?)?.toInt() ?? 0)}',
                      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                    ),
                    trailing: Icon(
                      isSelected ? Icons.filter_alt_rounded : Icons.folder_open_rounded,
                      color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF9CA3AF),
                    ),
                    onTap: () {
                      setState(() {
                        _selectedDeviceId = d['id']?.toString();
                        _selectedDeviceName = dName;
                        _selectedTab = 0;
                      });
                    },
                  ),
                );
              },
            ),
          const SizedBox(height: 18),

          // Storage Drives / Volumes Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Storage Drives & Nodes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              TextButton.icon(
                onPressed: () => _openModalSheet(_AddVolumeSheet(onAdded: _refreshAllData)),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text('Add Drive'),
              ),
            ],
          ),
          if (volumes.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('Primary Cloud Storage active', style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            )
          else
            ...volumes.map(
              (v) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.storage_rounded, color: Color(0xFF3B82F6)),
                  title: Text(
                    (v['volume_name'] ?? 'Storage Volume').toString(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${v['mount_path'] ?? ''}\nUsed: ${formatBytes((v['used_capacity_bytes'] as num?)?.toInt() ?? 0)}',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),

          // Connected Server Card
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_rounded, color: Color(0xFF3B82F6)),
              title: const Text('Connected Server', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _baseUrl.isEmpty ? 'Not Configured' : _baseUrl,
                style: const TextStyle(color: Color(0xFF9CA3AF)),
              ),
              trailing: TextButton(
                onPressed: _showServerDialog,
                child: const Text('Change'),
              ),
            ),
          ),
          const SizedBox(height: 22),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              side: const BorderSide(color: Color(0xFFEF4444)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text(
              'Sign Out',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              await ApiService.logout();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// REUSABLE SUB-WIDGETS
// =============================================================================
class _IconBadge extends StatelessWidget {
  final String cat;
  const _IconBadge({required this.cat});

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(cat);
    return Container(
      color: color.withAlpha(35),
      child: Center(
        child: Icon(categoryIcon(cat), color: color, size: 26),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// IN-APP PHOTO PREVIEWER WITH ZOOM, DOWNLOAD & DELETE
// =============================================================================
class PhotoViewerScreen extends StatelessWidget {
  final String fileName;
  final String imageUrl;
  final VoidCallback onDownload;
  final Future<void> Function()? onDelete;

  const PhotoViewerScreen({
    super.key,
    required this.fileName,
    required this.imageUrl,
    required this.onDownload,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          fileName,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            tooltip: 'Download Photo',
            onPressed: onDownload,
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
              tooltip: 'Delete Photo',
              onPressed: () => onDelete!.call(),
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (_, __, ___) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_rounded, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('Failed to load preview', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool isActive;

  const _StatusPill({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// =============================================================================
// ACCOUNT RECOVERY MODAL (RECOVERY KEY / 2FA TOTP / TELEGRAM OTP)
// =============================================================================
class _ForgotPasswordSheet extends StatefulWidget {
  final String initialServerUrl;
  final String initialUsername;

  const _ForgotPasswordSheet({
    required this.initialServerUrl,
    required this.initialUsername,
  });

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  String _method = 'telegram';
  late final TextEditingController _serverCtrl;
  late final TextEditingController _userCtrl;
  final TextEditingController _recoveryKeyCtrl = TextEditingController();
  final TextEditingController _totpSecretCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _newPwdCtrl = TextEditingController();
  bool _isBusy = false;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: widget.initialServerUrl);
    _userCtrl = TextEditingController(text: widget.initialUsername);
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _recoveryKeyCtrl.dispose();
    _totpSecretCtrl.dispose();
    _codeCtrl.dispose();
    _newPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendTelegramOtp() async {
    final url = _serverCtrl.text.trim();
    final user = _userCtrl.text.trim();
    if (url.isEmpty || user.isEmpty) {
      setState(() => _infoMessage = 'Enter Server Address and Username first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _infoMessage = 'Sending OTP to linked Telegram Bot...';
    });

    try {
      final res = await ApiService.requestTelegramReset(serverUrl: url, username: user);
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _infoMessage = res['message']?.toString() ?? 'OTP sent to Telegram!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _infoMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _submitReset() async {
    final url = _serverCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final newPwd = _newPwdCtrl.text;

    if (url.isEmpty || user.isEmpty || newPwd.length < 6) {
      setState(() => _infoMessage = 'Enter server URL, username & password (6+ chars).');
      return;
    }

    setState(() {
      _isBusy = true;
      _infoMessage = null;
    });

    try {
      if (_method == 'telegram') {
        await ApiService.resetWithTelegramOtp(
          serverUrl: url,
          username: user,
          otpCode: _codeCtrl.text.trim(),
          newPassword: newPwd,
        );
      } else if (_method == 'key') {
        await ApiService.recoverWithKey(
          serverUrl: url,
          username: user,
          recoveryKey: _recoveryKeyCtrl.text.trim(),
          newPassword: newPwd,
        );
      } else {
        await ApiService.recoverWithTotp(
          serverUrl: url,
          username: user,
          totpSecret: _totpSecretCtrl.text.trim(),
          code: _codeCtrl.text.trim(),
          newPassword: newPwd,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successfully! Please sign in.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _infoMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Recover Account Password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              'Preserves your AES-256 Master Key so existing encrypted files remain readable.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Telegram OTP'),
                  selected: _method == 'telegram',
                  onSelected: (_) => setState(() => _method = 'telegram'),
                ),
                ChoiceChip(
                  label: const Text('Recovery Key'),
                  selected: _method == 'key',
                  onSelected: (_) => setState(() => _method = 'key'),
                ),
                ChoiceChip(
                  label: const Text('2FA App'),
                  selected: _method == 'totp',
                  onSelected: (_) => setState(() => _method = 'totp'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _serverCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Server Address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_method == 'telegram') ...[
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _sendTelegramOtp,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send 6-Digit OTP to Telegram'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '6-Digit Telegram OTP Code',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ] else if (_method == 'key') ...[
              TextField(
                controller: _recoveryKeyCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Emergency Recovery Key (DG-XXXX-...)',
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              TextField(
                controller: _totpSecretCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Authenticator Base32 Secret Key',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Current 6-Digit 2FA Code',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _newPwdCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'New Password (min 6 characters)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_infoMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _infoMessage!,
                style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
              onPressed: _isBusy ? null : _submitReset,
              child: Text(
                _isBusy ? 'Processing...' : 'Reset Password',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// STORAGE CLEANER & DUPLICATE SCANNER MODAL
// =============================================================================
class _CleanerModalSheet extends StatefulWidget {
  const _CleanerModalSheet();

  @override
  State<_CleanerModalSheet> createState() => _CleanerModalSheetState();
}

class _CleanerModalSheetState extends State<_CleanerModalSheet> {
  bool _isScanning = false;
  Map<String, dynamic>? _report;
  String? _error;

  Future<void> _runScan() async {
    setState(() {
      _isScanning = true;
      _error = null;
    });

    try {
      final res = await ApiService.scanDuplicates();
      if (!mounted) return;
      setState(() {
        _report = res;
        _isScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sets = (_report?['duplicateSets'] as List<dynamic>? ?? []);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '🧹 Storage Cleaner & Duplicates',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              'Scans mounted cloud & local storage drives plus ZIP archives to find duplicate files.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
              onPressed: _isScanning ? null : _runScan,
              icon: _isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search_rounded, color: Colors.white),
              label: Text(
                _isScanning ? 'Scanning Storage...' : 'Start Deep Duplicate Scan',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444))),
            ],
            if (_report != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981).withAlpha(90)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scanned ${_report!['scannedTotalFiles'] ?? 0} files',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Duplicate groups: ${_report!['duplicateGroupsCount'] ?? 0}  •  Reclaimable: ${_report!['totalReclaimableMB'] ?? '0.00'} MB',
                      style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (sets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '🎉 Awesome! Zero duplicate files detected on storage.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF9CA3AF)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: sets.length,
                    itemBuilder: (_, idx) {
                      final entry = sets[idx] as Map<String, dynamic>;
                      final paths = (entry['files'] as List<dynamic>? ?? []);
                      final size = (entry['size'] as num?)?.toInt() ?? 0;
                      return Card(
                        color: const Color(0xFF0F172A),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Group #${idx + 1} (${formatBytes(size)} each)',
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...paths.map(
                                (p) => Text(
                                  '• $p',
                                  style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 2FA TOTP AUTHENTICATOR SETUP MODAL
// =============================================================================
class _TotpSetupSheet extends StatefulWidget {
  final bool isAlreadyEnabled;
  final Future<void> Function() onActivated;

  const _TotpSetupSheet({required this.isAlreadyEnabled, required this.onActivated});

  @override
  State<_TotpSetupSheet> createState() => _TotpSetupSheetState();
}

class _TotpSetupSheetState extends State<_TotpSetupSheet> {
  String? _secret;
  String? _authUri;
  final TextEditingController _pwdCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _pwdCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateSecret() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final res = await ApiService.setupTotp();
      if (!mounted) return;
      setState(() {
        _secret = res['secret']?.toString();
        _authUri = res['authUri']?.toString();
        _isBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isBusy = false;
      });
    }
  }

  Future<void> _activate() async {
    if (_secret == null || _pwdCtrl.text.isEmpty || _codeCtrl.text.trim().length != 6) {
      setState(() => _error = 'Enter your current password and 6-digit code.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await ApiService.enableTotp(
        secret: _secret!,
        code: _codeCtrl.text.trim(),
        password: _pwdCtrl.text,
      );
      await widget.onActivated();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔐 2FA Authenticator activated & linked to your vault!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '🔐 2FA Authenticator Security',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isAlreadyEnabled
                  ? '2FA is active. You can generate a new secret key below to rotate it.'
                  : 'Link Google or Microsoft Authenticator as a fail-safe backup for your vault.',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_secret == null)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                ),
                onPressed: _isBusy ? null : _generateSecret,
                icon: const Icon(Icons.qr_code_rounded, color: Colors.white),
                label: Text(
                  _isBusy ? 'Generating...' : 'Generate Authenticator Secret Key',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3B82F6).withAlpha(110)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1. Add setup key manually in Google Authenticator:',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _secret!,
                      style: const TextStyle(
                        color: Color(0xFF93C5FD),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy Key'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _secret!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Secret key copied!')),
                            );
                          },
                        ),
                        if (_authUri != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.link_rounded, size: 16),
                            label: const Text('Copy URI'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _authUri!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('otpauth:// URI copied!')),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pwdCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Current Account Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '6-Digit Authenticator Code',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                onPressed: _isBusy ? null : _activate,
                child: Text(
                  _isBusy ? 'Verifying...' : 'Activate 2FA',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// CHANGE PASSWORD MODAL
// =============================================================================
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final TextEditingController _currentCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cur = _currentCtrl.text;
    final next = _newCtrl.text;
    if (cur.isEmpty || next.length < 6) {
      setState(() => _error = 'Enter current password & new password (6+ chars).');
      return;
    }
    if (next != _confirmCtrl.text) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ApiService.changePassword(currentPassword: cur, newPassword: next);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔑 Password changed! Existing encrypted files remain safe.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '🔑 Change Account Password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _currentCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'New Password (min 6 characters)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
              onPressed: _isSaving ? null : _submit,
              child: Text(
                _isSaving ? 'Updating...' : 'Update Password',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TELEGRAM BOT RECOVERY & ALERTS MODAL
// =============================================================================
class _TelegramSetupSheet extends StatefulWidget {
  final bool isLinked;
  final String? maskedChatId;
  final Future<void> Function() onUpdated;

  const _TelegramSetupSheet({
    required this.isLinked,
    required this.maskedChatId,
    required this.onUpdated,
  });

  @override
  State<_TelegramSetupSheet> createState() => _TelegramSetupSheetState();
}

class _TelegramSetupSheetState extends State<_TelegramSetupSheet> {
  final TextEditingController _tokenCtrl = TextEditingController();
  final TextEditingController _chatIdCtrl = TextEditingController();
  final TextEditingController _pwdCtrl = TextEditingController();
  bool _alertsEnabled = true;
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _chatIdCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveTelegram() async {
    if (_tokenCtrl.text.trim().isEmpty ||
        _chatIdCtrl.text.trim().isEmpty ||
        _pwdCtrl.text.isEmpty) {
      setState(() => _error = 'Enter Bot Token, Chat ID, and current password.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await ApiService.setupTelegram(
        botToken: _tokenCtrl.text.trim(),
        chatId: _chatIdCtrl.text.trim(),
        currentPassword: _pwdCtrl.text,
        alertsEnabled: _alertsEnabled,
      );
      await widget.onUpdated();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✈️ Telegram linked! Verification message sent to your chat.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isBusy = false;
      });
    }
  }

  Future<void> _unlink() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await ApiService.unlinkTelegram();
      await widget.onUpdated();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telegram recovery unlinked.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '✈️ Telegram Bot Recovery & Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isLinked
                  ? 'Currently linked to Chat ${widget.maskedChatId ?? "****"}. Enter new credentials to update or tap Unlink below.'
                  : 'Create your private bot via @BotFather & get your numeric Chat ID from @userinfobot, then send /start to your bot.',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _tokenCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Telegram Bot Token (@BotFather)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _chatIdCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Numeric Chat ID (@userinfobot)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pwdCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Current Account Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Login & Security Alerts',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              value: _alertsEnabled,
              onChanged: (val) => setState(() => _alertsEnabled = val),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
              onPressed: _isBusy ? null : _saveTelegram,
              child: Text(
                _isBusy ? 'Verifying Bot...' : 'Link & Send Test Message',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            if (widget.isLinked) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                ),
                onPressed: _isBusy ? null : _unlink,
                child: const Text('Unlink Telegram'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ADD STORAGE DRIVE / VOLUME MODAL
// =============================================================================
class _AddVolumeSheet extends StatefulWidget {
  final Future<void> Function() onAdded;

  const _AddVolumeSheet({required this.onAdded});

  @override
  State<_AddVolumeSheet> createState() => _AddVolumeSheetState();
}

class _AddVolumeSheetState extends State<_AddVolumeSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _pathCtrl = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final path = _pathCtrl.text.trim();
    if (name.isEmpty || path.isEmpty) {
      setState(() => _error = 'Enter both volume name and server mount path.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ApiService.addStorageVolume(volumeName: name, mountPath: path);
      await widget.onAdded();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('💾 Storage volume added successfully!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '💾 Add Storage Volume / Drive',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Drive Name (e.g. External-HDD-2TB)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Server Folder Path (e.g. /mnt/hdd2)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
              onPressed: _isSaving ? null : _save,
              child: Text(
                _isSaving ? 'Adding...' : 'Mount Storage Drive',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
