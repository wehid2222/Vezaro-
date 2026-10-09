import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/download_item.dart';
import 'services/download_history_store.dart';
import 'services/download_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VezaroApp());
}

class VezaroApp extends StatefulWidget {
  const VezaroApp({super.key});

  @override
  State<VezaroApp> createState() => _VezaroAppState();
}

class _VezaroAppState extends State<VezaroApp> {
  String _language = 'ar';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _language = prefs.getString('language') ?? 'ar';
      _ready = true;
    });
  }

  Future<void> _changeLanguage(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', value);
    if (mounted) setState(() => _language = value);
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF8B72FF);
    return MaterialApp(
      title: 'Vezaro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101018),
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF1D1B2A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101018),
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1D1B2A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: _ready
          ? VezaroHomePage(language: _language, onLanguageChanged: _changeLanguage)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class VezaroHomePage extends StatefulWidget {
  const VezaroHomePage({
    super.key,
    required this.language,
    required this.onLanguageChanged,
  });

  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<VezaroHomePage> createState() => _VezaroHomePageState();
}

class _VezaroHomePageState extends State<VezaroHomePage> {
  static const Color _background = Color(0xFF101018);
  static const Color _surface = Color(0xFF1D1B2A);
  static const Color _accent = Color(0xFF8B72FF);
  static const Color _paleAccent = Color(0xFFB9AAFF);

  final TextEditingController _urlController = TextEditingController();
  final DownloadService _downloadService = DownloadService();
  final DownloadHistoryStore _historyStore = DownloadHistoryStore();
  final List<DownloadItem> _downloads = <DownloadItem>[];

  int _selectedIndex = 0;
  bool _loadingHistory = true;
  bool _downloading = false;
  double _progress = 0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  CancelToken? _cancelToken;
  DownloadLocation _defaultLocation = DownloadLocation.app;

  bool get _ar => widget.language == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    _restoreState();
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final storedLocation = prefs.getString('default_download_location');
    final records = await _historyStore.load();
    final valid = <DownloadItem>[];
    for (final record in records) {
      if (await _downloadService.exists(record)) valid.add(record);
    }
    if (!mounted) return;
    setState(() {
      _downloads
        ..clear()
        ..addAll(valid);
      _defaultLocation = storedLocation == 'downloads'
          ? DownloadLocation.downloads
          : DownloadLocation.app;
      _loadingHistory = false;
    });
    if (valid.length != records.length) {
      await _historyStore.save(valid);
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel('screen_disposed');
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _homePage(),
      _downloadsPage(),
      _placeholderPage(
        Icons.favorite_rounded,
        _t('المفضلة', 'Favorites'),
        _t('ستتوفر المفضلة في تحديث لاحق.', 'Favorites will be available in a future update.'),
      ),
      _settingsPage(),
    ];

    return Directionality(
      textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          title: const Text('Vezaro', style: TextStyle(fontWeight: FontWeight.w800)),
          leading: const Icon(Icons.downloading_rounded, color: _paleAccent),
        ),
        body: IndexedStack(index: _selectedIndex, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => setState(() => _selectedIndex = index),
          destinations: <NavigationDestination>[
            NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: _t('الرئيسية', 'Home')),
            NavigationDestination(icon: const Icon(Icons.download_outlined), selectedIcon: const Icon(Icons.download_done_rounded), label: _t('التنزيلات', 'Downloads')),
            NavigationDestination(icon: const Icon(Icons.favorite_outline), selectedIcon: const Icon(Icons.favorite_rounded), label: _t('المفضلة', 'Favorites')),
            NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings_rounded), label: _t('الإعدادات', 'Settings')),
          ],
        ),
      ),
    );
  }

  Widget _homePage() => ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF39276F), _surface],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.bolt_rounded, size: 42, color: Colors.white),
                const SizedBox(height: 14),
                Text(_t('نزّل بذكاء مع Vezaro', 'Download smarter with Vezaro'), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(_t('نزّل الملفات المباشرة التي تملك حق حفظها، واختر مكان تخزينها.', 'Download direct files you are authorized to save and choose where to store them.'), style: TextStyle(color: Colors.white.withValues(alpha: 0.78), height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(_t('رابط التنزيل', 'Download URL'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: _t('ألصق رابط الملف المباشر هنا', 'Paste a direct file URL'),
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                tooltip: _t('مسح الرابط', 'Clear URL'),
                onPressed: _downloading ? null : _urlController.clear,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _accent),
              onPressed: _downloading ? null : _chooseLocationAndDownload,
              icon: const Icon(Icons.download_rounded),
              label: Text(_downloading ? _t('جارٍ التنزيل...', 'Downloading...') : _t('فحص الرابط والتنزيل', 'Check link & download')),
            ),
          ),
          if (_downloading) ...<Widget>[
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(child: Text(_t('جارٍ تنزيل الملف', 'Downloading file'))),
                Text(_totalBytes > 0 ? '${(_progress * 100).toStringAsFixed(0)}%' : _t('جارٍ الاتصال', 'Connecting')),
                IconButton(
                  tooltip: _t('إلغاء التنزيل', 'Cancel download'),
                  onPressed: () => _cancelToken?.cancel('user_cancelled'),
                  icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                ),
              ],
            ),
            LinearProgressIndicator(value: _totalBytes > 0 ? _progress : null, color: _paleAccent),
            const SizedBox(height: 6),
            Text('${_formatBytes(_receivedBytes)}${_totalBytes > 0 ? ' / ${_formatBytes(_totalBytes)}' : ''}', style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 28),
          Text(_t('مصمم للتنزيلات اليومية', 'Built for everyday downloads'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _feature(Icons.folder_outlined, _t('اختر مكان الحفظ', 'Choose storage'), _t('داخل التطبيق أو في مجلد Downloads العام.', 'App storage or the public Downloads folder.')),
          _feature(Icons.fact_check_outlined, _t('تحقق من الملف', 'File validation'), _t('نتحقق من استجابة الخادم ونرفض صفحات HTML بدل الملفات.', 'Validate server responses and reject HTML pages masquerading as files.')),
          _feature(Icons.history_rounded, _t('سجل محفوظ', 'Persistent history'), _t('يُحفظ سجل التنزيلات ويُراجع عند فتح التطبيق.', 'Download history is saved and checked when the app opens.')),
          const SizedBox(height: 8),
          Text(_t('ملاحظة: روابط صفحات منصات الفيديو قد تتطلب موصلًا خاصًا؛ لا تُعد مدعومة بمجرد لصقها.', 'Note: video-platform pages may require a dedicated connector and are not supported merely by pasting the page URL.'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60)),
        ],
      );

  Future<void> _chooseLocationAndDownload() async {
    final uri = DownloadService.parseHttpUrl(_urlController.text);
    if (uri == null) {
      _showMessage(_t('أدخل رابط HTTP أو HTTPS صحيحًا.', 'Enter a valid HTTP or HTTPS URL.'));
      return;
    }
    if (DownloadService.isKnownPlatformPage(uri)) {
      _showMessage(_t('هذا رابط صفحة منصة. لم يُفعّل مستخرج لهذه المنصة بعد؛ جرّب رابط الملف المباشر.', 'This is a platform page URL. An extractor is not enabled for this platform yet; try a direct media URL.'));
      return;
    }
    if (uri.scheme.toLowerCase() == 'http') {
      final continueWithHttp = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('اتصال غير مشفّر', 'Unencrypted connection')),
          content: Text(_t(
            'هذا الرابط يستخدم HTTP غير المشفّر. قد يتمكن الآخرون من رؤية البيانات أثناء النقل. هل تريد المتابعة؟',
            'This URL uses unencrypted HTTP. Others may be able to observe data in transit. Continue?',
          )),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t('إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_t('متابعة', 'Continue'))),
          ],
        ),
      );
      if (continueWithHttp != true) return;
    }

    var selected = _defaultLocation;
    var remember = false;
    final result = await showModalBottomSheet<DownloadLocation>(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_t('اختر مكان الحفظ', 'Choose save location'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                RadioListTile<DownloadLocation>(
                  value: DownloadLocation.app,
                  groupValue: selected,
                  onChanged: (value) => setSheetState(() => selected = value!),
                  title: Text(_t('داخل التطبيق', 'App storage')),
                  subtitle: Text(_t('خاص بالتطبيق وقد يُحذف عند إلغاء تثبيته.', 'Private to the app; removed when the app is uninstalled.')),
                  secondary: const Icon(Icons.lock_outline),
                ),
                RadioListTile<DownloadLocation>(
                  value: DownloadLocation.downloads,
                  groupValue: selected,
                  onChanged: (value) => setSheetState(() => selected = value!),
                  title: Text(_t('مجلد Downloads', 'Public Downloads')),
                  subtitle: Text(_t('يمكن الوصول إليه من مدير الملفات.', 'Accessible from your file manager.')),
                  secondary: const Icon(Icons.folder_open_rounded),
                ),
                CheckboxListTile(
                  value: remember,
                  onChanged: (value) => setSheetState(() => remember = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('تذكّر اختياري كمكان افتراضي', 'Remember as default location')),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, selected),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(_t('بدء التنزيل', 'Start download')),
                  ),
                ),
                TextButton(onPressed: () => Navigator.pop(sheetContext), child: Text(_t('إلغاء', 'Cancel'))),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    if (remember) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('default_download_location', result == DownloadLocation.downloads ? 'downloads' : 'app');
      if (mounted) setState(() => _defaultLocation = result);
    }
    await _startDownload(uri.toString(), result);
  }

  Future<void> _startDownload(String url, DownloadLocation location) async {
    if (_downloading) return;
    if (location == DownloadLocation.downloads) {
      final sdkInt = await DownloadService.androidSdkInt();
      if (sdkInt >= 23 && sdkInt < 29) {
        final permission = await Permission.storage.request();
        if (!permission.isGranted) {
          _showMessage(_t('لم يُمنح إذن التخزين؛ لم يبدأ التنزيل.', 'Storage permission was not granted; download did not start.'));
          return;
        }
      }
    }
    final token = CancelToken();
    setState(() {
      _downloading = true;
      _progress = 0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _cancelToken = token;
    });
    try {
      final item = await _downloadService.download(
        url: url,
        location: location,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            _progress = total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : 0.0;
          });
        },
      );
      if (!mounted) return;
      setState(() => _downloads.insert(0, item));
      var historySaved = true;
      try {
        await _historyStore.save(_downloads);
      } catch (_) {
        historySaved = false;
      }
      _showMessage(historySaved
          ? _t('اكتمل التنزيل: ${item.name}', 'Download complete: ${item.name}')
          : _t('تم حفظ الملف، لكن تعذر حفظ سجل التنزيلات.', 'File saved, but download history could not be saved.'));
      _urlController.clear();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        _showMessage(_t('تم إلغاء التنزيل.', 'Download cancelled.'));
      } else {
        _showMessage(_t('تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مجددًا.', 'Could not connect to the server. Check your connection and retry.'));
      }
    } on DownloadFailure catch (error) {
      _showMessage(_failureMessage(error.messageKey));
    } on PlatformException catch (_) {
      _showMessage(_t('تعذر الوصول إلى التخزين المطلوب.', 'Could not access the selected storage.'));
    } catch (_) {
      _showMessage(_t('حدث خطأ غير متوقع. لم يُسجّل التنزيل على أنه ناجح.', 'An unexpected error occurred. The download was not marked as successful.'));
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _cancelToken = null;
        });
      }
    }
  }

  String _failureMessage(String key) {
    final messages = <String, List<String>>{
      'invalidUrl': ['الرابط غير صالح. استخدم رابط HTTP أو HTTPS.', 'The URL is invalid. Use an HTTP or HTTPS URL.'],
      'platformNeedsExtractor': ['يتطلب رابط المنصة مستخرجًا خاصًا غير مفعّل حاليًا.', 'This platform URL requires a dedicated extractor that is not enabled yet.'],
      'httpError': ['رفض الخادم الطلب أو أعاد استجابة غير ناجحة.', 'The server rejected the request or returned an unsuccessful response.'],
      'missingFile': ['لم يُنشأ ملف التنزيل.', 'The download file was not created.'],
      'emptyFile': ['أعاد الخادم ملفًا فارغًا.', 'The server returned an empty file.'],
      'webPageNotFile': ['الرابط أعاد صفحة ويب وليس ملفًا مباشرًا.', 'The URL returned a webpage instead of a direct file.'],
      'accessDenied': ['يتطلب الرابط تسجيل الدخول أو لا يسمح بالوصول.', 'The URL requires sign-in or access is denied.'],
      'timeout': ['انتهت مهلة الاتصال أو التنزيل.', 'The connection or download timed out.'],
      'networkError': ['حدث خطأ في الشبكة أثناء التنزيل.', 'A network error occurred during download.'],
      'publicSaveFailed': ['فشل حفظ الملف في مجلد Downloads.', 'Failed to save the file to Downloads.'],
      'storagePermissionRequired': ['يتطلب أندرويد إذن التخزين لإصدار النظام هذا.', 'This Android version requires storage permission.'],
    };
    final pair = messages[key] ?? ['فشل التنزيل. حاول مرة أخرى.', 'Download failed. Please try again.'];
    return _t(pair[0], pair[1]);
  }

  Widget _downloadsPage() {
    if (_loadingHistory) return const Center(child: CircularProgressIndicator());
    if (_downloads.isEmpty) {
      return _placeholderPage(Icons.download_done_rounded, _t('التنزيلات', 'Downloads'), _t('لا توجد تنزيلات بعد. ستظهر الملفات الناجحة هنا.', 'No downloads yet. Completed files will appear here.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _downloads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _downloads[index];
        return Card(
          color: _surface,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: _accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
              child: Icon(_iconForMime(item.mimeType), color: _paleAccent),
            ),
            onTap: () => _openDownload(item),
            title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text('${_formatBytes(item.sizeBytes)} • ${item.isPublic ? _t('Downloads العام', 'Public Downloads') : _t('تخزين التطبيق', 'App storage')}\n${_formatDate(item.createdAt)}', maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: _t('حذف الملف', 'Delete file'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmDelete(item),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDownload(DownloadItem item) async {
    final opened = await _downloadService.open(item);
    if (!mounted) return;
    if (!opened) {
      _showMessage(_t('لا يوجد تطبيق متوافق لفتح هذا الملف.', 'No compatible app was found to open this file.'));
    }
  }

  Future<void> _confirmDelete(DownloadItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('حذف الملف؟', 'Delete file?')),
        content: Text(_t('سيتم حذف ${item.name} من موقع الحفظ.', 'This will delete ${item.name} from its saved location.')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t('حذف', 'Delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _downloadService.delete(item);
      if (!mounted) return;
      setState(() => _downloads.removeWhere((entry) => entry.id == item.id));
      try {
        await _historyStore.save(_downloads);
        _showMessage(_t('تم حذف الملف.', 'File deleted.'));
      } catch (_) {
        _showMessage(_t('حُذف الملف، لكن تعذر تحديث سجل التنزيلات.', 'File deleted, but the download history could not be updated.'));
      }
    } catch (_) {
      _showMessage(_t('تعذر حذف الملف. تحقق من صلاحيات الوصول.', 'Could not delete the file. Check access permissions.'));
    }
  }

  Widget _settingsPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Text(_t('الإعدادات', 'Settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Card(
            color: _surface,
            child: Column(
              children: <Widget>[
                ListTile(leading: const Icon(Icons.language_rounded, color: _paleAccent), title: Text(_t('لغة التطبيق', 'App language'))),
                RadioListTile<String>(value: 'ar', groupValue: widget.language, title: const Text('العربية'), onChanged: (value) { if (value != null) widget.onLanguageChanged(value); }),
                RadioListTile<String>(value: 'en', groupValue: widget.language, title: const Text('English'), onChanged: (value) { if (value != null) widget.onLanguageChanged(value); }),
              ],
            ),
          ),
          Card(
            color: _surface,
            child: Column(
              children: <Widget>[
                ListTile(leading: const Icon(Icons.folder_outlined, color: _paleAccent), title: Text(_t('مكان الحفظ الافتراضي', 'Default save location')),
                  subtitle: Text(_defaultLocation == DownloadLocation.app ? _t('داخل التطبيق', 'App storage') : _t('مجلد Downloads', 'Public Downloads'))),
                RadioListTile<DownloadLocation>(value: DownloadLocation.app, groupValue: _defaultLocation, title: Text(_t('داخل التطبيق', 'App storage')), onChanged: (value) => _setDefaultLocation(value!)),
                RadioListTile<DownloadLocation>(value: DownloadLocation.downloads, groupValue: _defaultLocation, title: Text(_t('مجلد Downloads', 'Public Downloads')), onChanged: (value) => _setDefaultLocation(value!)),
              ],
            ),
          ),
          Card(color: _surface, child: ListTile(leading: const Icon(Icons.info_outline_rounded, color: _paleAccent), title: Text(_t('حول Vezaro', 'About Vezaro')), subtitle: const Text('Vezaro 1.1.0 • Flutter'))),
          const SizedBox(height: 12),
          Text(_t('يحمّل التطبيق الملفات المباشرة. دعم صفحات منصات الفيديو يحتاج إلى موصلات مستقلة واختبارات لكل منصة.', 'Vezaro downloads direct files. Video platform pages require separate connectors and platform-specific testing.'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60)),
        ],
      );

  Future<void> _setDefaultLocation(DownloadLocation value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_download_location', value == DownloadLocation.downloads ? 'downloads' : 'app');
    if (mounted) setState(() => _defaultLocation = value);
  }

  Widget _feature(IconData icon, String title, String subtitle) => Card(
        color: _surface,
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(leading: Icon(icon, color: _paleAccent, size: 29), title: Text(title), subtitle: Text(subtitle)),
      );

  Widget _placeholderPage(IconData icon, String title, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 68, color: _paleAccent),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static IconData _iconForMime(String mime) {
    if (mime.startsWith('video/')) return Icons.movie_outlined;
    if (mime.startsWith('audio/')) return Icons.music_note_rounded;
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}
