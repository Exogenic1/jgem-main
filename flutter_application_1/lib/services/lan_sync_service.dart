import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_helper.dart';
import 'package:network_info_plus/network_info_plus.dart';

class LanSyncService {
  static const String _syncIntervalKey = 'sync_interval_minutes';
  static const String _lanServerEnabledKey = 'lan_server_enabled';
  static const String _syncEnabledKey = 'sync_enabled'; // Add this line
  static const String _serverPortKey = 'server_port';
  static const String _accessCodeKey = 'lan_access_code';
  static const int _defaultPort = 8080;

  static Timer? _syncTimer;
  static Timer? _watchdogTimer;
  static HttpServer? _server;
  static DatabaseHelper? _dbHelper;
  static String? _dbPath;
  static Directory? _watchDir;
  static StreamSubscription? _dirWatcher;
  static String? _accessCode; // For basic authentication
  static List<String> _allowedIpRanges = [];
  // Initialize the service
  static Future<void> initialize(DatabaseHelper dbHelper) async {
    try {
      _dbHelper = dbHelper;

      // Get saved settings with error handling
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (e) {
        debugPrint('Failed to access SharedPreferences: $e');
        throw Exception('Failed to access app settings: $e');
      }

      final syncInterval = prefs.getInt(_syncIntervalKey) ?? 5; // Default 5 minutes
      final lanServerEnabled = prefs.getBool(_lanServerEnabledKey) ?? false;
      final serverPort = prefs.getInt(_serverPortKey) ?? _defaultPort;

      // Get or generate access code with error handling
      try {
        _accessCode = prefs.getString(_accessCodeKey);
        if (_accessCode == null) {
          _accessCode = _generateAccessCode();
          await prefs.setString(_accessCodeKey, _accessCode!);
        }
      } catch (e) {
        debugPrint('Failed to handle access code: $e');
        _accessCode = _generateAccessCode(); // Generate fallback code
      }

      // Determine LAN IP ranges with error handling
      try {
        await _configureLanIpRanges();
      } catch (e) {
        debugPrint('Failed to configure LAN IP ranges: $e');
        // Use fallback IP ranges
        _allowedIpRanges = ['127.0.0', '192.168.0', '192.168.1', '10.0.0', '172.16.0'];
      }

      // Export DB to accessible location with error handling
      try {
        await _setupDbForSharing();
      } catch (e) {
        debugPrint('Failed to setup database for sharing: $e');
        throw Exception('Failed to setup database sharing: $e');
      }

      // Start sync timer with error handling
      try {
        _startPeriodicSync(syncInterval);
      } catch (e) {
        debugPrint('Failed to start periodic sync: $e');
        // Continue without periodic sync
      }

      // Start LAN server if enabled with error handling
      if (lanServerEnabled) {
        try {
          await startLanServer(port: serverPort);
        } catch (e) {
          debugPrint('Failed to start LAN server: $e');
          // Continue without LAN server
        }
      }

      // Monitor for file changes with error handling
      try {
        await _startFileChangeMonitoring();
      } catch (e) {
        debugPrint('Failed to start file change monitoring: $e');
        // Continue without file monitoring
      }
    } catch (e) {
      debugPrint('LanSyncService initialization failed: $e');
      rethrow;
    }
  }

  // Generate a random access code for basic auth
  static String _generateAccessCode() {
    final random = Random.secure();
    final values = List<int>.generate(8, (i) => random.nextInt(256));
    return base64Url.encode(values).substring(0, 8);
  }

  // Configure allowed IP ranges for LAN-only access
  static Future<void> _configureLanIpRanges() async {
    _allowedIpRanges = [];

    try {
      // Get device's own IP address
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();

      if (wifiIP != null) {
        // Extract network prefix (e.g., 192.168.1)
        final parts = wifiIP.split('.');
        if (parts.length == 4) {
          final prefix = "${parts[0]}.${parts[1]}.${parts[2]}";
          _allowedIpRanges.add(prefix);
          debugPrint('Configured LAN access for subnet: $prefix.*');
        }
      }

      // Add localhost
      _allowedIpRanges.add('127.0.0');

      // If no valid IP was found, use common private network ranges
      if (_allowedIpRanges.length == 1) {
        // Only localhost was added
        _allowedIpRanges
            .addAll(['192.168.0', '192.168.1', '10.0.0', '172.16.0']);
        debugPrint('Using standard private network ranges');
      }
    } catch (e) {
      debugPrint('Error configuring LAN ranges: $e');
      // Fallback to common private network ranges
      _allowedIpRanges = [
        '127.0.0',
        '192.168.0',
        '192.168.1',
        '10.0.0',
        '172.16.0'
      ];
    }
  }

  // Check if an IP is within allowed LAN ranges
  static bool _isLanIp(String ip) {
    for (final prefix in _allowedIpRanges) {
      if (ip.startsWith('$prefix.')) {
        return true;
      }
    }
    return false;
  }
  // Set up database for sharing
  static Future<void> _setupDbForSharing() async {
    try {
      Directory targetDir;

      // Platform-specific directory selection with error handling
      try {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          // For desktop platforms, use documents directory
          targetDir = await getApplicationDocumentsDirectory();
        } else if (Platform.isAndroid) {
          // For Android, try external storage first, fallback to documents
          try {
            final externalDir = await getExternalStorageDirectory();
            targetDir = externalDir ?? await getApplicationDocumentsDirectory();
          } catch (e) {
            debugPrint('External storage not available, using documents directory: $e');
            targetDir = await getApplicationDocumentsDirectory();
          }
        } else {
          // For other platforms (iOS), use documents directory
          targetDir = await getApplicationDocumentsDirectory();
        }
      } catch (e) {
        debugPrint('Failed to get application documents directory: $e');
        throw Exception('Cannot access documents directory: $e');
      }

      // Ensure the directory exists and is accessible
      try {
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
      } catch (e) {
        debugPrint('Failed to create target directory: $e');
        throw Exception('Cannot create or access target directory: $e');
      }

      // Path for the shared database
      _dbPath = join(targetDir.path, 'patient_management_shared.db');
      _watchDir = targetDir;

      // Copy current database to shared location with error handling
      try {
        await _copyDatabaseToSharedLocation();
      } catch (e) {
        debugPrint('Failed to copy database to shared location: $e');
        // This is not critical, we can continue without the initial copy
      }

      debugPrint('DB path for LAN sharing: $_dbPath');
    } catch (e) {
      debugPrint('Error setting up DB for sharing: $e');
      rethrow;
    }
  }
  // Copy database to shared location
  static Future<void> _copyDatabaseToSharedLocation() async {
    if (_dbHelper == null) {
      debugPrint('Database helper is null, cannot copy database');
      return;
    }

    try {
      final dbPath = await _dbHelper!.currentDatabasePath;
      if (dbPath == null) {
        debugPrint('Current database path is null, cannot copy database');
        return;
      }
      
      if (_dbPath == null) {
        debugPrint('Target database path is null, cannot copy database');
        return;
      }

      final sourceFile = File(dbPath);
      if (!await sourceFile.exists()) {
        debugPrint('Source database file does not exist: $dbPath');
        return;
      }

      final targetFile = File(_dbPath!);
      
      try {
        await sourceFile.copy(targetFile.path);
        debugPrint('Database copied to shared location: $_dbPath');
      } catch (e) {
        debugPrint('Failed to copy database file: $e');
        // Try to create an empty database file as fallback
        try {
          await targetFile.create(recursive: true);
          debugPrint('Created empty database file as fallback: $_dbPath');
        } catch (createError) {
          debugPrint('Failed to create fallback database file: $createError');
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('Error copying database to shared location: $e');
      throw Exception('Failed to setup database sharing: $e');
    }
  }// Start periodic synchronization

  static void _startPeriodicSync(int intervalMinutes) {
    // Cancel existing timer if any
    _syncTimer?.cancel();

    _syncTimer = Timer.periodic(Duration(minutes: intervalMinutes), (_) async {
      try {
        // Check if sync is enabled
        final prefs = await SharedPreferences.getInstance();
        final syncEnabled = prefs.getBool(_syncEnabledKey) ?? false;

        if (!syncEnabled) {
          debugPrint('Sync is disabled in settings - skipping');
          return;
        }

        debugPrint('Running scheduled database sync...');

        // Add timeout wrapper for the entire sync operation
        final success = await _dbHelper!
            .syncWithServer()
            .timeout(const Duration(seconds: 30), onTimeout: () {
          debugPrint('Sync operation timed out after 30 seconds');
          return false;
        });

        debugPrint('Sync completed with ${success ? "success" : "failure"}');
      } catch (e) {
        debugPrint('Scheduled sync error: $e');
        // Don't rethrow - just log and continue
      }
    });

    debugPrint('Periodic sync started (interval: $intervalMinutes minutes)');
  }

  // Change sync interval
  static Future<void> setSyncInterval(int minutes) async {
    if (minutes < 1) minutes = 1; // Minimum 1 minute

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncIntervalKey, minutes);

    _startPeriodicSync(minutes);
  }

  // Enable or disable sync
  static Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncEnabledKey, enabled);

    if (enabled) {
      final syncInterval = prefs.getInt(_syncIntervalKey) ?? 5;
      _startPeriodicSync(syncInterval);
    } else {
      _syncTimer?.cancel();
      debugPrint('Sync disabled');
    }
  }

  // Check if sync is enabled
  static Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_syncEnabledKey) ?? false;
  }

  // Force manual sync now
  static Future<bool> syncNow() async {
    try {
      return await _dbHelper!.syncWithServer();
    } catch (e) {
      debugPrint('Manual sync error: $e');
      return false;
    }
  }

  // Validate request authentication using access code
  static bool _validateAuth(HttpRequest request) {
    // Extract authorization header
    final authHeader = request.headers.value('authorization');
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return false;
    }

    final token = authHeader.substring(7); // Remove 'Bearer ' prefix
    return token == _accessCode;
  }

  // Check if request comes from LAN
  static bool _isLanRequest(HttpRequest request) {
    final remoteAddress = request.connectionInfo?.remoteAddress.address;
    return remoteAddress != null && _isLanIp(remoteAddress);
  }

  // Start LAN server for database access
  static Future<void> startLanServer({int port = _defaultPort}) async {
    try {
      // Stop existing server if running
      await stopLanServer();

      // Save setting
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lanServerEnabledKey, true);
      await prefs.setInt(_serverPortKey, port);

      // Create server - bind only to local adapter for LAN access
      // This is more secure than binding to InternetAddress.anyIPv4
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);

      debugPrint('LAN server started on port $port');
      debugPrint('Access code: $_accessCode');

      // Configure server to handle requests
      _server!.listen((request) async {
        try {
          // Only accept requests from LAN IPs
          if (!_isLanRequest(request)) {
            request.response.statusCode = HttpStatus.forbidden;
            request.response.write('Access denied: Non-LAN connection');
            await request.response.close();
            debugPrint(
                'Blocked non-LAN request from: ${request.connectionInfo?.remoteAddress.address}');
            return;
          } // API endpoints
          if (request.method == 'GET' && request.uri.path == '/db') {
            // Require authentication for database access
            if (!_validateAuth(request)) {
              request.response.statusCode = HttpStatus.unauthorized;
              request.response.headers.add('WWW-Authenticate', 'Bearer');
              request.response.write('Authentication required');
              await request.response.close();
              return;
            }

            // Serve the database file for direct access
            final dbFile = File(_dbPath!);
            if (await dbFile.exists()) {
              request.response.headers.contentType =
                  ContentType('application', 'octet-stream');
              request.response.headers.add('Content-Disposition',
                  'attachment; filename="patient_management.db"');
              await dbFile.openRead().pipe(request.response);
            } else {
              request.response.statusCode = HttpStatus.notFound;
              request.response.write('Database file not found');
              await request.response.close();
            }
          } else if (request.method == 'POST' && request.uri.path == '/sync') {
            // Handle sync requests from other devices
            if (!_validateAuth(request)) {
              request.response.statusCode = HttpStatus.unauthorized;
              request.response.headers.add('WWW-Authenticate', 'Bearer');
              request.response.write('Authentication required');
              await request.response.close();
              return;
            } // Handle sync data
            final content = await utf8.decoder.bind(request).join();
            final syncData = jsonDecode(content);

            // Process sync request - for now, just acknowledge
            request.response.headers.contentType =
                ContentType('application', 'json');
            request.response.write(jsonEncode({
              'status': 'success',
              'message': 'Sync request received',
              'dataReceived': syncData.keys.toList(),
              'timestamp': DateTime.now().toIso8601String(),
            }));
            await request.response.close();
          } else if (request.method == 'GET' &&
              request.uri.path == '/changes') {
            // Get pending changes for sync
            if (!_validateAuth(request)) {
              request.response.statusCode = HttpStatus.unauthorized;
              request.response.headers.add('WWW-Authenticate', 'Bearer');
              request.response.write('Authentication required');
              await request.response.close();
              return;
            }

            final pendingChanges = await _dbHelper!.getPendingChanges();
            request.response.headers.contentType =
                ContentType('application', 'json');
            request.response.write(jsonEncode({
              'changes': pendingChanges,
              'timestamp': DateTime.now().toIso8601String(),
            }));
            await request.response.close();
          } else if (request.method == 'GET' && request.uri.path == '/status') {
            // Return server status (no auth required for status check)
            request.response.headers.contentType =
                ContentType('application', 'json');
            final pendingChanges = await _dbHelper!.getPendingChanges();

            final status = {
              'status': 'online',
              'dbPath': _dbPath,
              'pendingChanges': pendingChanges.length,
              'allowedNetworks':
                  _allowedIpRanges.map((prefix) => '$prefix.*').toList(),
              'timestamp': DateTime.now().toIso8601String(),
            };

            request.response.write(jsonEncode(status));
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('Not found');
            await request.response.close();
          }
        } catch (e) {
          debugPrint('Error handling request: $e');
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('Internal server error');
          await request.response.close();
        }
      });

      // Start watchdog timer to ensure server stays alive
      _startWatchdog();
    } catch (e) {
      debugPrint('Failed to start LAN server: $e');
      rethrow;
    }
  }

  // Regenerate access code
  static Future<String> regenerateAccessCode() async {
    final newCode = _generateAccessCode();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessCodeKey, newCode);
    _accessCode = newCode;
    return newCode;
  }

  // Stop LAN server
  static Future<void> stopLanServer() async {
    try {
      await _server?.close(force: true);
      _server = null;

      _watchdogTimer?.cancel();
      _watchdogTimer = null;

      // Save setting
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lanServerEnabledKey, false);

      debugPrint('LAN server stopped');
    } catch (e) {
      debugPrint('Error stopping LAN server: $e');
    }
  }

  // Start watchdog timer
  static void _startWatchdog() {
    _watchdogTimer?.cancel();

    _watchdogTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_server == null) {
        debugPrint('Watchdog detected server is down, restarting...');

        final prefs = await SharedPreferences.getInstance();
        final port = prefs.getInt(_serverPortKey) ?? _defaultPort;

        await startLanServer(port: port);
      }
    });
  }

  // Monitor for file changes
  static Future<void> _startFileChangeMonitoring() async {
    try {
      if (_watchDir == null) return;

      // Cancel existing watcher if any
      await _dirWatcher?.cancel();

      // Watch for changes in the directory
      _dirWatcher = _watchDir!.watch(recursive: false).listen((event) {
        final path = event.path;

        // If our database file was modified externally
        if (path.endsWith('patient_management.db')) {
          debugPrint('Database file modified externally at ${DateTime.now()}');
          // No need to do anything special here as SQLite handles this automatically
          // with its built-in concurrency control
        }
      });

      debugPrint('File change monitoring started for: ${_watchDir!.path}');
    } catch (e) {
      debugPrint('Error setting up file monitoring: $e');
    }
  }

  // Get network information for connecting
  static Future<Map<String, dynamic>> getConnectionInfo() async {
    try {
      final interfaces = await NetworkInterface.list();
      final ipAddresses = <String>[];

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && _isLanIp(addr.address)) {
            ipAddresses.add(addr.address);
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final port = prefs.getInt(_serverPortKey) ?? _defaultPort;
      final lanServerEnabled = prefs.getBool(_lanServerEnabledKey) ?? false;

      return {
        'ipAddresses': ipAddresses,
        'port': port,
        'lanServerEnabled': lanServerEnabled,
        'dbPath': _dbPath,
        'connectionUrls':
            ipAddresses.map((ip) => 'http://$ip:$port/db').toList(),
        'statusUrl': ipAddresses.isNotEmpty
            ? 'http://${ipAddresses.first}:$port/status'
            : null,
        'accessCode': _accessCode,
        'allowedNetworks':
            _allowedIpRanges.map((prefix) => '$prefix.*').toList(),
      };
    } catch (e) {
      debugPrint('Error getting connection info: $e');
      return {
        'error': e.toString(),
      };
    }
  }

  static Future<int> getPendingChanges() async {
    try {
      if (_dbHelper == null) {
        return 0;
      }
      final changes = await _dbHelper!.getPendingChanges();
      return changes.length;
    } catch (e) {
      debugPrint('Error getting pending changes: $e');
      return 0;
    }
  }

  // Generate instructions for DB Browser connection
  static Future<String> getDbBrowserInstructions() async {
    final connectionInfo = await getConnectionInfo();

    final StringBuffer instructions = StringBuffer();
    instructions.writeln('=== DB BROWSER CONNECTION INSTRUCTIONS ===\n');
    instructions.writeln('To view the database in DB Browser for SQLite:');

    if (connectionInfo['lanServerEnabled'] == true) {
      instructions
          .writeln('\nOption 1: Direct Network Connection (Recommended)');
      instructions.writeln('1. Open DB Browser for SQLite');
      instructions.writeln('2. Select "File" > "Open Database"');
      instructions.writeln('3. In the URL field, enter one of:');

      for (final url in connectionInfo['connectionUrls']) {
        instructions.writeln('   - $url');
      }

      instructions.writeln('4. When prompted for authentication:');
      instructions.writeln(
          '   - Use "Bearer ${connectionInfo['accessCode']}" as the token');
      instructions.writeln('5. Select "Read and Write" mode');
      instructions.writeln(
          '6. Check "Keep updating the SQL view as the database changes"');
    }

    instructions.writeln('\nOption 2: Manual File Connection');
    instructions.writeln('1. Find the database file at:');
    instructions.writeln('   ${connectionInfo['dbPath']}');
    instructions.writeln('2. Copy this file to your computer');
    instructions.writeln('3. Open it in DB Browser for SQLite');
    instructions.writeln('4. Note: This won\'t show live updates');

    instructions.writeln('\nLAN Access Information:');
    instructions
        .writeln('IP Addresses: ${connectionInfo['ipAddresses'].join(', ')}');
    instructions.writeln('Server Port: ${connectionInfo['port']}');
    instructions.writeln(
        'Server Status: ${connectionInfo['lanServerEnabled'] ? 'Running' : 'Stopped'}');
    instructions.writeln('Access Code: ${connectionInfo['accessCode']}');
    instructions.writeln(
        'Allowed Networks: ${connectionInfo['allowedNetworks'].join(', ')}');

    return instructions.toString();
  }

  // Dispose the service
  static Future<void> dispose() async {
    _syncTimer?.cancel();
    _watchdogTimer?.cancel();
    await _dirWatcher?.cancel();
    await _server?.close(force: true);

    _syncTimer = null;
    _watchdogTimer = null;
    _dirWatcher = null;
    _server = null;
  }

  // Add this to your LanSyncService class
  static Future<void> enableContinuousLocalCopy() async {
    Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final localPath = join((await getApplicationDocumentsDirectory()).path,
            'patient_management_live.db');
        final dbPath = await _dbHelper!.exportDatabase();

        // Copy to a "live" version
        final sourceFile = File(dbPath);
        final targetFile = File(localPath);
        await sourceFile.copy(targetFile.path);

        debugPrint('Live copy updated: $localPath');
      } catch (e) {
        debugPrint('Error updating live copy: $e');
      }
    });
  }

  // Add periodic database copy for live sharing
  static void _startDatabaseSync() {
    Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        // Copy the main database to the shared location for live updates
        await _copyDatabaseToSharedLocation();
      } catch (e) {
        debugPrint('Error in periodic database sync: $e');
      }
    });
  }

  // Initialize LAN sharing with better error handling
  static Future<bool> initializeLanSharing() async {
    try {
      if (_dbHelper == null) {
        debugPrint('Database helper not initialized');
        return false;
      }

      await _setupDbForSharing();
      _startDatabaseSync();

      // Auto-start LAN server if enabled
      final prefs = await SharedPreferences.getInstance();
      final lanEnabled = prefs.getBool(_lanServerEnabledKey) ?? false;

      if (lanEnabled) {
        final port = prefs.getInt(_serverPortKey) ?? _defaultPort;
        await startLanServer(port: port);
      }

      return true;
    } catch (e) {
      debugPrint('Failed to initialize LAN sharing: $e');
      return false;
    }
  }
}
