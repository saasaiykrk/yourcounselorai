import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

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
/// "Print / Save as PDF" button asks the app, which opens the phone's print / save-as-PDF dialog
/// (the server leaves the button out otherwise).
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
  InAppWebViewController? _web;
  late String _title = widget.page.title;
  double _progress = 0;
  bool _canGoBack = false;
  bool _failed = false;

  Future<void> _syncBack() async {
    final back = await _web?.canGoBack() ?? false;
    if (mounted && back != _canGoBack) setState(() => _canGoBack = back);
  }

  Future<void> _print() async {
    if (!widget.canPrint) return;
    await _web?.printCurrentPage(settings: PrintJobSettings(jobName: _title));
  }

  void _retry() {
    setState(() => _failed = false);
    _web?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.page.url)));
  }

  @override
  Widget build(BuildContext context) {
    final home = Uri.parse(widget.page.url);
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _web?.goBack();
        await _syncBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 3),
                )
              : null,
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.page.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: true,
                incognito: true, // nothing from the pages is kept on the phone
                cacheEnabled: false,
                supportMultipleWindows: false,
                javaScriptCanOpenWindowsAutomatically: false,
                allowFileAccess: false,
                allowContentAccess: false,
                builtInZoomControls: true,
                displayZoomControls: false,
              ),
              onWebViewCreated: (c) {
                _web = c;
                c.addJavaScriptHandler(
                  handlerName: 'ycPrint',
                  callback: (_) {
                    _print();
                    return null;
                  },
                );
              },
              shouldOverrideUrlLoading: (c, action) async {
                final url = action.request.url;
                if (url == null || !action.isForMainFrame) return NavigationActionPolicy.ALLOW;
                switch (linkTarget(home, url)) {
                  case LinkTarget.stay:
                    return NavigationActionPolicy.ALLOW;
                  case LinkTarget.phone:
                    launchUrl(url, mode: LaunchMode.externalApplication).ignore();
                    return NavigationActionPolicy.CANCEL;
                  case LinkTarget.block:
                    return NavigationActionPolicy.CANCEL;
                }
              },
              onProgressChanged: (c, p) {
                if (mounted) setState(() => _progress = p / 100);
              },
              onTitleChanged: (c, t) {
                final title = cleanTitle(t ?? '');
                if (mounted && title.isNotEmpty && !title.startsWith('http')) setState(() => _title = title);
              },
              onUpdateVisitedHistory: (c, url, isReload) => _syncBack(),
              onLoadStop: (c, url) => _syncBack(),
              onReceivedError: (c, request, error) {
                if (request.isForMainFrame ?? true) {
                  if (mounted) setState(() => _failed = true);
                }
              },
            ),
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
