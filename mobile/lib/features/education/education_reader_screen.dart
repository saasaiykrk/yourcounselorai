import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/education/education_repository.dart';
import '../../core/theme/app_theme.dart';

/// Where a tap inside a page goes.
enum LinkTarget {
  /// Another education page (or a jump within this one): stays in the app.
  stay,

  /// A phone number, email or outside website: handed to the phone.
  phone,

  /// Anything else: ignored.
  block,
}

LinkTarget linkTarget(Uri page, Uri target) {
  if (target.scheme == page.scheme && target.host == page.host && target.path.startsWith('/learn/')) {
    return LinkTarget.stay;
  }
  if (const {'tel', 'mailto', 'sms', 'https', 'http'}.contains(target.scheme)) return LinkTarget.phone;
  return LinkTarget.block;
}

/// "YourCounselor | Therapy Comparison Chart" → "Therapy Comparison Chart".
String cleanTitle(String t) => t.replaceAll(RegExp(r'^\s*YourCounselor\s*\|\s*|\s*\|\s*YourCounselor\s*$'), '').trim();

/// One education page inside the app, under the app's own bar. With a plan, the page's
/// "Print / Save as PDF" button hands the app the page as it looks now (every section open, no
/// scripts), which the app prints through the phone's print / save-as-PDF dialog. The server leaves
/// the button out otherwise, and the in-app view ignores the page's own print call.
class EducationReaderScreen extends StatelessWidget {
  const EducationReaderScreen({super.key, required this.page, required this.canPrint});

  final EducationPage page;
  final bool canPrint;

  @override
  Widget build(BuildContext context) => page.kind == 'handout'
      ? _PdfHandoutView(page: page, canPrint: canPrint)
      : _WebPageView(page: page, canPrint: canPrint);
}

class _WebPageView extends StatefulWidget {
  const _WebPageView({required this.page, required this.canPrint});

  final EducationPage page;
  final bool canPrint;

  @override
  State<_WebPageView> createState() => _WebPageViewState();
}

class _WebPageViewState extends State<_WebPageView> {
  late final Uri _home = Uri.parse(widget.page.url);
  late String _title = widget.page.title;
  late final WebViewController _web;
  double _progress = 0;
  bool _canGoBack = false;
  bool _failed = false;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final url = Uri.tryParse(request.url);
            if (url == null) return NavigationDecision.prevent;
            switch (linkTarget(_home, url)) {
              case LinkTarget.stay:
                return NavigationDecision.navigate;
              case LinkTarget.phone:
                launchUrl(url, mode: LaunchMode.externalApplication).ignore();
                return NavigationDecision.prevent;
              case LinkTarget.block:
                return NavigationDecision.prevent;
            }
          },
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _failed = false);
          },
          onPageFinished: (_) async {
            final t = cleanTitle(await _web.getTitle() ?? '');
            if (mounted && t.isNotEmpty && !t.startsWith('http')) setState(() => _title = t);
            await _syncBack();
          },
          onUrlChange: (_) => _syncBack(),
          onWebResourceError: (e) {
            if ((e.isForMainFrame ?? true) && mounted) setState(() => _failed = true);
          },
        ),
      )
      // The page's Print / Save as PDF button (only there with a plan) sends the page as it looks now.
      ..addJavaScriptChannel('YCApp', onMessageReceived: (m) => _print(m.message))
      ..loadRequest(_home);
  }

  @override
  void dispose() {
    // Nothing from the pages is kept on the phone.
    _web.clearCache().ignore();
    _web.clearLocalStorage().ignore();
    super.dispose();
  }

  Future<void> _syncBack() async {
    final back = await _web.canGoBack();
    if (mounted && back != _canGoBack) setState(() => _canGoBack = back);
  }

  Future<void> _print(String html) async {
    if (!widget.canPrint || _printing || !html.startsWith('<!doctype html>')) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: _title,
        // The phone's own web engine lays the page out, so it prints exactly as it reads. Deprecated only
        // in favour of building PDFs from widgets, which can't reproduce these pages; still implemented.
        // ignore: deprecated_member_use
        onLayout: (format) => Printing.convertHtml(format: format, html: html, baseUrl: widget.page.url),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Couldn't open printing. Please try again.")));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _web.loadRequest(_home);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress < 1 || _printing;
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _web.goBack();
        await _syncBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: busy
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _printing || _progress == 0 ? null : _progress, minHeight: 3),
                )
              : null,
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _web),
            if (_failed)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: _Problem(onRetry: _retry),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PdfHandoutView extends StatefulWidget {
  const _PdfHandoutView({required this.page, required this.canPrint});

  final EducationPage page;
  final bool canPrint;

  @override
  State<_PdfHandoutView> createState() => _PdfHandoutViewState();
}

class _PdfHandoutViewState extends State<_PdfHandoutView> {
  late Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() async {
    final dio = Dio(
      BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60)),
    );
    final r = await dio.get<List<int>>(widget.page.url, options: Options(responseType: ResponseType.bytes));
    return Uint8List.fromList(r.data ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.page.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snap) {
          if (snap.hasError) return _Problem(onRetry: () => setState(() => _bytes = _load()));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final bytes = snap.data!;
          // Print and share (save) only with a plan; otherwise read-only, with no action bar.
          return PdfPreview(
            build: (_) async => bytes,
            useActions: widget.canPrint,
            allowPrinting: widget.canPrint,
            allowSharing: widget.canPrint,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: widget.page.url.split('?').first.split('/').last,
          );
        },
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Couldn't load this page. Check your connection.",
            style: AppText.bodyMuted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
