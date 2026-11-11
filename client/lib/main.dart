import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withAlpha(30),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF3B82F6).withAlpha(100),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.cloud_done_rounded,
                    size: 56,
                    color: Color(0xFF3B82F6),
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
  String _searchQuery = '';
  String _selectedCategory = 'All';
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

      final files = await filesFuture;
      final status = await statusFuture;
      final devices = await devicesFuture;

      if (!mounted) return;
      setState(() {
        _allFiles = files;
        _storageStatus = status;
        _devices = devices;
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
      final matchesSearch = _searchQuery.isEmpty ||
          name.toLowerCase().contains(_searchQuery.toLowerCase());
      final category = detectCategory(name, mime);
      final matchesCat =
          _selectedCategory == 'All' || category == _selectedCategory;
      return matchesSearch && matchesCat;
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

  void _openFilePreviewOrSheet(Map<String, dynamic> file) {
    final name = (file['file_name'] ?? '').toString();
    final mime = (file['mime_type'] ?? '').toString();
    final category = detectCategory(name, mime);
    final fileId = file['id'].toString();

    if (category == 'Photos' && _baseUrl.isNotEmpty && _token.isNotEmpty) {
      final imageUrl = '$_baseUrl/api/v1/files/$fileId/stream?token=$_token';
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoViewerScreen(
            fileName: name,
            imageUrl: imageUrl,
            onDownload: () => _downloadCloudFile(file),
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
              const SizedBox(height: 20),
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
              const SizedBox(height: 8),
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
            const Icon(Icons.cloud_done_rounded, color: Color(0xFF3B82F6), size: 24),
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
        trailing: IconButton(
          icon: const Icon(Icons.download_for_offline_rounded, color: Color(0xFF3B82F6)),
          tooltip: 'Download',
          onPressed: () => _downloadCloudFile(file),
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
  // TAB 2: STORAGE QUOTA, DEVICES & ACCOUNT
  // ===========================================================================
  Widget _buildStorageTab() {
    final userStats = _storageStatus?['userStats'] as Map<String, dynamic>?;
    final totalBytes = (userStats?['total_user_bytes'] as num?)?.toInt() ?? 0;
    final totalFiles = (userStats?['total_files'] as num?)?.toInt() ?? 0;
    final quotaBytes = (_storageStatus?['cloudQuotaBytes'] as num?)?.toInt() ?? 161061273600;
    final usedPercent = quotaBytes > 0 ? ((totalBytes / quotaBytes) * 100).clamp(0, 100) : 0;

    return RefreshIndicator(
      onRefresh: _refreshAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF3B82F6).withAlpha(40),
                        child: const Icon(Icons.person_rounded, color: Color(0xFF3B82F6)),
                      ),
                      const SizedBox(width: 12),
                      Column(
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
                    ],
                  ),
                  const SizedBox(height: 18),
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
          const SizedBox(height: 16),

          // Server Settings Card
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
          const SizedBox(height: 16),

          // Connected Devices
          const Text(
            'Linked Devices',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
              (d) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    (d['device_type'] ?? '') == 'web'
                        ? Icons.computer_rounded
                        : Icons.smartphone_rounded,
                    color: const Color(0xFF10B981),
                  ),
                  title: Text(
                    (d['device_name'] ?? 'Unknown Device').toString(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${d['total_files_count'] ?? 0} files  •  ${formatBytes((d['total_used_bytes'] as num?)?.toInt() ?? 0)}',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),
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
// IN-APP PHOTO PREVIEWER WITH ZOOM & DOWNLOAD
// =============================================================================
class PhotoViewerScreen extends StatelessWidget {
  final String fileName;
  final String imageUrl;
  final VoidCallback onDownload;

  const PhotoViewerScreen({
    super.key,
    required this.fileName,
    required this.imageUrl,
    required this.onDownload,
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
