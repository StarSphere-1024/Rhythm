import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'core/backup_files.dart';
import 'core/planner.dart';
import 'core/reminders.dart';
import 'features/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Noto Sans SC'], license);
  });
  runApp(const _Startup());
}

ThemeData rhythmTheme(
  Brightness brightness, {
  Color seedColor = const Color(0xff208d78),
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'NotoSansSC',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}

class RhythmApp extends StatelessWidget {
  const RhythmApp({super.key, required this.planner, required this.reminders});
  final Planner planner;
  final ReminderService reminders;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Rhythm · 节律',
    debugShowCheckedModeBanner: false,
    theme: rhythmTheme(Brightness.light),
    darkTheme: rhythmTheme(Brightness.dark),
    themeMode: ThemeMode.system,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    home: RhythmShell(planner: planner, reminders: reminders),
  );
}

class _Startup extends StatefulWidget {
  const _Startup();
  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  Planner? _planner;
  ReminderService? _reminders;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final planner = await Planner.load();
      final reminders = ReminderService(planner);
      // Reminder failures are reported by the service, never a reason to reset data.
      try {
        await reminders.initialize();
      } catch (_) {
        // Task planning remains available; settings exposes reminder status.
      }
      if (!mounted) {
        reminders.dispose();
        planner.dispose();
        return;
      }
      setState(() {
        _planner = planner;
        _reminders = reminders;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _reminders?.dispose();
    _planner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_planner != null && _reminders != null) {
      return RhythmApp(planner: _planner!, reminders: _reminders!);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: rhythmTheme(Brightness.light),
      darkTheme: rhythmTheme(Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: _error == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text('正在打开节律…'),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          '暂时无法读取本地数据',
                          style: TextStyle(fontSize: 22),
                        ),
                        const SizedBox(height: 12),
                        const Text('原数据仍被保留。不会重置数据库或创建空白数据。请保留原文件，检查存储空间后重试。'),
                        const SizedBox(height: 12),
                        SelectableText('$_error'),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新读取'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await BackupFiles.exportRaw();
                            } catch (error) {
                              if (mounted) setState(() => _error = error);
                            }
                          },
                          icon: const Icon(Icons.save_alt),
                          label: const Text('导出原始数据以便恢复'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
