import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:crypto/crypto.dart';

// =========================================================================
// PRODUCTION AUTHENTICATION NOTE (Cognito / Firebase Auth Integration):
// For enterprise production deployments, this lightweight in-memory API Key
// gate would be replaced by:
// 1. AWS Cognito User Pools / Firebase Authentication:
//    - Multi-Factor Authentication (MFA), SAML/OIDC Single Sign-On, and RBAC.
// 2. JWT Bearer Tokens:
//    - The mobile client authenticates against Cognito/Firebase and retrieves
//      a short-lived JWT Access Token.
//    - Requests pass 'Authorization: Bearer <JWT>' instead of a static API Key.
// 3. API Gateway Cognito Authorizer / Lambda Authorizer:
//    - Decodes signature, validates claims, and enforces granular IAM permissions.
// =========================================================================

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // In-memory authentication state (never persisted to disk/SharedPreferences)
  String? _inMemoryApiKey;

  // Optional compile-time default via --dart-define=API_KEY=...
  static const String initialDefaultKey =
      String.fromEnvironment('API_KEY', defaultValue: '');

  @override
  void initState() {
    super.initState();
    if (initialDefaultKey.isNotEmpty) {
      _inMemoryApiKey = initialDefaultKey;
    }
  }

  void _handleLogin(String apiKey) {
    setState(() {
      _inMemoryApiKey = apiKey;
    });
  }

  void _handleLogout() {
    setState(() {
      _inMemoryApiKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telemetry Dashboard',
      theme: ThemeData.dark(),
      home: _inMemoryApiKey == null || _inMemoryApiKey!.isEmpty
          ? LoginScreen(onLoginSuccess: _handleLogin)
          : TelemetryScreen(
              apiKey: _inMemoryApiKey!,
              onLogout: _handleLogout,
            ),
    );
  }
}

// --- Login / Shared-Secret Auth Gate Screen ---
// --- Login / Shared-Secret Auth Gate Screen ---
class LoginScreen extends StatefulWidget {
  final ValueChanged<String> onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String buildTimeApiKey =
      String.fromEnvironment('API_KEY', defaultValue: '');

  final TextEditingController _keyController = TextEditingController(
    text: buildTimeApiKey,
  );
  bool _obscureText = true;
  String? _errorMessage;

  void _attemptLogin() {
    final enteredKey = _keyController.text.trim();
    if (enteredKey.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter an API Key';
      });
      return;
    }

    // Authenticate with in-memory key directly into the live dashboard
    widget.onLoginSuccess(enteredKey);
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 54,
                      color: Colors.cyan,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Telemetry Engineer Portal',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter authorized API Key to access live host telemetry & orchestration.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    if (buildTimeApiKey.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amberAccent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.amberAccent,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'API Key not configured at build time (--dart-define=API_KEY). Please enter your key below.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    TextField(
                      controller: _keyController,
                      obscureText: _obscureText,
                      decoration: InputDecoration(
                        labelText: 'API Key (x-api-key)',
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureText = !_obscureText;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        errorText: _errorMessage,
                      ),
                      onSubmitted: (_) => _attemptLogin(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan[700],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.lock_open),
                        label: const Text(
                          'Authenticate & Enter',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _attemptLogin,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Main Telemetry Dashboard Screen ---
class TelemetryScreen extends StatefulWidget {
  final String apiKey;
  final VoidCallback onLogout;

  const TelemetryScreen({
    super.key,
    required this.apiKey,
    required this.onLogout,
  });

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen> {
  List telemetryData = [];
  List<String> availableServers = [];
  String? selectedServer; // null indicates "All servers"

  bool isLoading = true;
  bool isBannerDismissed = false;
  String? lastSpikeId;
  Timer? _pollingTimer;
  int _ticksCount = 0;

  // Configurable API base URL & default EC2 instance ID via --dart-define
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: String.fromEnvironment(
      'API_URL',
      defaultValue: 'https://7qw0khxma2.execute-api.ap-southeast-2.amazonaws.com',
    ),
  );

  static const String defaultInstanceId = String.fromEnvironment(
    'EC2_INSTANCE_ID',
    defaultValue: 'i-0abcdef1234567890',
  );

  final String getMetricsUrl = apiBaseUrl.endsWith('/')
      ? '${apiBaseUrl}GetMetrics'
      : '$apiBaseUrl/GetMetrics';

  final String getServersUrl = apiBaseUrl.endsWith('/')
      ? '${apiBaseUrl}GetServers'
      : '$apiBaseUrl/GetServers';

  final String executeCommandUrl = apiBaseUrl.endsWith('/')
      ? '${apiBaseUrl}ExecuteCommand'
      : '$apiBaseUrl/ExecuteCommand';

  Future<void> fetchServers() async {
    try {
      final response = await http.get(
        Uri.parse(getServersUrl),
        headers: {'x-api-key': widget.apiKey},
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          setState(() {
            availableServers = List<String>.from(decoded);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> fetchTelemetry() async {
    try {
      String targetUrl = getMetricsUrl;
      if (selectedServer != null &&
          selectedServer!.isNotEmpty &&
          selectedServer != 'ALL') {
        targetUrl =
            '$getMetricsUrl?server_id=${Uri.encodeComponent(selectedServer!)}';
      }

      final response = await http.get(
        Uri.parse(targetUrl),
        headers: {'x-api-key': widget.apiKey},
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          setState(() {
            // Reverse data so oldest is first for the graph left-to-right flow
            telemetryData = List.from(decoded.reversed);
            isLoading = false;
          });
        }
      } else if (response.statusCode == 403) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              'Access Denied: Invalid or revoked API Key (HTTP 403).',
            ),
          ),
        );
        widget.onLogout();
      }
    } catch (e) {
      if (isLoading) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> confirmAndKillProcess(
    BuildContext context, {
    required String cmd,
    required int pid,
    String? serverId,
  }) async {
    final targetInstanceId =
        (serverId != null && serverId.isNotEmpty)
            ? serverId
            : defaultInstanceId;

    final confirmationCode = sha256.convert(utf8.encode('$targetInstanceId:$pid:$cmd')).toString().substring(0, 8);
    final baseProcessName = cmd.trim().split(' ').first.split('/').last;
    final TextEditingController textController = TextEditingController();
    bool forceKill = false;
    bool isMatch = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.amberAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kill Process Guardrail',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target: $targetInstanceId\nPID: $pid\nProcess: "$cmd"',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.key, size: 16, color: Colors.amberAccent),
                          const SizedBox(width: 8),
                          Text(
                            'Confirmation Code: $confirmationCode',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'To confirm termination, enter the 8-char code (or process name):',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: textController,
                      autofocus: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        isDense: true,
                        hintText: 'Enter "$confirmationCode" or "$baseProcessName"',
                        errorText: textController.text.isNotEmpty && !isMatch
                            ? 'Code or name does not match'
                            : null,
                      ),
                      onChanged: (val) {
                        final input = val.trim();
                        setDialogState(() {
                          isMatch = (input.toLowerCase() == confirmationCode.toLowerCase()) ||
                              (input == cmd.trim()) ||
                              (input.toLowerCase() == baseProcessName.toLowerCase());
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: forceKill,
                      title: const Text(
                        'Force Kill (SIGKILL -9)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Unchecked sends SIGTERM (-15) for graceful exit',
                        style: TextStyle(fontSize: 11.5, color: Colors.white60),
                      ),
                      onChanged: (bool? val) {
                        setDialogState(() {
                          forceKill = val ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    textController.dispose();
                    Navigator.of(ctx).pop(null);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isMatch ? Colors.redAccent : Colors.grey[700],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isMatch
                      ? () {
                          final res = {
                            'confirmed': true,
                            'forceKill': forceKill
                          };
                          textController.dispose();
                          Navigator.of(ctx).pop(res);
                        }
                      : null,
                  child: Text(
                    forceKill ? 'Force Kill (-9)' : 'Terminate (-15)',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result['confirmed'] == true && mounted) {
      await _executeKillCommand(
        targetInstanceId: targetInstanceId,
        pid: pid,
        cmd: cmd,
        forceKill: result['forceKill'] == true,
      );
    }
  }

  Future<void> _executeKillCommand({
    required String targetInstanceId,
    required int pid,
    required String cmd,
    required bool forceKill,
  }) async {
    final signalName = forceKill ? 'SIGKILL (-9)' : 'SIGTERM (-15)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dispatching $signalName for "$cmd" (PID: $pid)...'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final response = await http.post(
        Uri.parse(executeCommandUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': widget.apiKey,
        },
        body: json.encode({
          'instance_id': targetInstanceId,
          'pid': pid,
          'process_name': cmd,
          'force_kill': forceKill,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final commandId = data['command_id'] ?? 'dispatched';
        final signal = data['signal'] ?? (forceKill ? 'SIGKILL' : 'SIGTERM');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green[800],
            content: Text(
              'Success: Sent $signal for PID $pid "$cmd" (SSM Command: $commandId)',
            ),
          ),
        );
      } else {
        String msg;
        try {
          final errorBody = json.decode(response.body);
          msg = errorBody['error'] ?? 'HTTP ${response.statusCode}';
        } catch (_) {
          msg = 'HTTP ${response.statusCode}: ${response.body}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: response.statusCode == 403
                ? Colors.orange[900]
                : Colors.red[800],
            duration: const Duration(seconds: 5),
            content: Text(
              response.statusCode == 403
                  ? 'Guardrail Rejection (403): $msg'
                  : 'Failed to terminate process: $msg',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red[800],
          content: Text('Error communicating with AWS: $e'),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    fetchServers();
    fetchTelemetry();
    // Auto-refresh every 3 seconds for live dashboard updates
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      fetchTelemetry();
      _ticksCount++;
      if (_ticksCount % 4 == 0) {
        fetchServers();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check if the latest telemetry record has top_processes
    Map<String, dynamic>? latestRecord;
    if (telemetryData.isNotEmpty) {
      latestRecord = Map<String, dynamic>.from(telemetryData.last);
    }

    final topProcesses =
        latestRecord != null ? latestRecord['top_processes'] : null;
    String? warningMessage;
    String? topCmd;
    int? topPid;

    if (topProcesses != null &&
        topProcesses is List &&
        topProcesses.isNotEmpty) {
      final firstProc = topProcesses[0];
      topCmd = firstProc['cmd'] ?? 'unknown';
      final cpu = firstProc['cpu'] ?? 0;
      topPid =
          (firstProc['pid'] is num) ? (firstProc['pid'] as num).toInt() : null;
      warningMessage = 'High CPU detected — top process: $topCmd ($cpu%)';

      // If a new spike arrives, re-enable banner if previously dismissed
      final currentSpikeKey = '${latestRecord?['created_at']}_$topCmd';
      if (lastSpikeId != currentSpikeKey) {
        lastSpikeId = currentSpikeKey;
        isBannerDismissed = false;
      }
    } else {
      // Reset dismissal state when load returns to normal
      isBannerDismissed = false;
      lastSpikeId = null;
    }

    final showBanner = warningMessage != null && !isBannerDismissed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Telemetry'),
        actions: [
          // Server Filter Dropdown
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.white24),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: (selectedServer != null &&
                        availableServers.contains(selectedServer))
                    ? selectedServer
                    : 'ALL',
                dropdownColor: const Color(0xFF1E222D),
                icon: const Icon(
                  Icons.dns_outlined,
                  color: Colors.cyan,
                  size: 18,
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                onChanged: (String? newValue) {
                  setState(() {
                    selectedServer = (newValue == 'ALL') ? null : newValue;
                    isLoading = true;
                  });
                  fetchTelemetry();
                },
                items: [
                  const DropdownMenuItem<String>(
                    value: 'ALL',
                    child: Text('All servers'),
                  ),
                  ...availableServers.map((server) {
                    return DropdownMenuItem<String>(
                      value: server,
                      child: Text(server),
                    );
                  }),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout (Clear API Key)',
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // --- Dismissible High CPU Warning Banner with Kill Process Action ---
                  if (showBanner) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 10.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.6),
                        ),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              warningMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          if (topPid != null && topCmd != null) ...[
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                  vertical: 6.0,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 15),
                              label: const Text(
                                'Kill Process',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () => confirmAndKillProcess(
                                context,
                                cmd: topCmd!,
                                pid: topPid!,
                                serverId: latestRecord?['server_id'],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.white70,
                            ),
                            onPressed: () {
                              setState(() {
                                isBannerDismissed = true;
                              });
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Text(
                    selectedServer == null
                        ? 'CPU & RAM Usage (%) — All Servers'
                        : 'CPU & RAM Usage (%) — $selectedServer',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // --- Graphical Chart Section ---
                  SizedBox(
                    height: 250,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: true),
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: true),
                        minY: 0,
                        maxY: 100,
                        lineBarsData: [
                          // CPU Line (Cyan)
                          LineChartBarData(
                            spots: telemetryData.asMap().entries.map((entry) {
                              int index = entry.key;
                              double cpu = (entry.value['cpu_percent'] as num)
                                  .toDouble();
                              return FlSpot(index.toDouble(), cpu);
                            }).toList(),
                            isCurved: true,
                            color: Colors.cyan,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                          ),
                          // RAM Line (Orange)
                          LineChartBarData(
                            spots: telemetryData.asMap().entries.map((entry) {
                              int index = entry.key;
                              double ram = (entry.value['ram_percent'] as num)
                                  .toDouble();
                              return FlSpot(index.toDouble(), ram);
                            }).toList(),
                            isCurved: true,
                            color: Colors.orange,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.square, color: Colors.cyan),
                      Text(' CPU %  '),
                      Icon(Icons.square, color: Colors.orange),
                      Text(' RAM %'),
                    ],
                  ),
                  const Divider(height: 26),
                  // --- Historical List Section ---
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      selectedServer == null
                          ? 'Recent Logs (All Servers)'
                          : 'Recent Logs ($selectedServer)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.builder(
                      itemCount: telemetryData.length,
                      itemBuilder: (context, index) {
                        final item = telemetryData[index];
                        final itemTopProcs = item['top_processes'];
                        final hasTopProcs = itemTopProcs != null &&
                            itemTopProcs is List &&
                            itemTopProcs.isNotEmpty;
                        final topProcStr = hasTopProcs
                            ? '\nTop: ${itemTopProcs[0]["cmd"]} (${itemTopProcs[0]["cpu"]}%)'
                            : '';
                        return Card(
                          child: ListTile(
                            title: Text('Server: ${item["server_id"]}'),
                            subtitle: Text(
                              'CPU: ${item["cpu_percent"]}% | RAM: ${item["ram_percent"]}%$topProcStr',
                            ),
                            trailing: hasTopProcs &&
                                    itemTopProcs[0]['pid'] != null
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    tooltip: 'Kill Process',
                                    onPressed: () => confirmAndKillProcess(
                                      context,
                                      cmd: itemTopProcs[0]['cmd'] ?? 'process',
                                      pid:
                                          (itemTopProcs[0]['pid'] as num).toInt(),
                                      serverId: item['server_id'],
                                    ),
                                  )
                                : Text('${item["ram_used_mb"]} MB'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            isLoading = true;
          });
          fetchServers();
          fetchTelemetry();
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
