import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/education/education_repository.dart';
import '../../core/theme/app_theme.dart';
import 'print_unlock.dart';

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

/// The education page a `/learn/<slug>` address shows, or null.
String? pageSlug(Uri? url) {
  final seg = url?.pathSegments ?? const <String>[];
  return seg.length == 2 && seg[0] == 'learn' && seg[1] != 'file' ? seg[1] : null;
}

/// "YourCounselor | Therapy Comparison Chart" → "Therapy Comparison Chart".
String cleanTitle(String t) => t.replaceAll(RegExp(r'^\s*YourCounselor\s*\|\s*|\s*\|\s*YourCounselor\s*$'), '').trim();

/// One Knowledge page inside the app, under the app's own bar. There is no page-wide print button:
/// printing goes through each module's own "Print or save as PDF" buttons (client handouts and
/// counsellor sheets). Unlocked (pricing off, a subscription, or a single print of that module), a
/// button hands the app the handout as the module would print it, and the app prints it through the
/// phone's print / save-as-PDF dialog. Locked, it asks the app, which offers a single print or the
/// subscriptions; after a confirmed payment the page is loaded again and the server unlocks it. The
/// Case History PDF has no buttons of its own, so its viewer keeps one.
class EducationReaderScreen extends StatelessWidget {
  const EducationReaderScreen({super.key, required this.page, this.offer});

  final EducationPage page;

  /// A single print for sale, if any.
  final PrintOffer? offer;

  @override
  Widget build(BuildContext context) =>
      page.kind == 'handout' ? _PdfHandoutView(page: page, offer: offer) : _WebPageView(page: page, offer: offer);
}

class _WebPageView extends ConsumerStatefulWidget {
  const _WebPageView({required this.page, this.offer});

  final EducationPage page;
  final PrintOffer? offer;

  @override
  ConsumerState<_WebPageView> createState() => _WebPageViewState();
}

class _WebPageViewState extends ConsumerState<_WebPageView> {
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
      // The module's own "Print or save as PDF" buttons (handouts, worksheets) send the handout to print,
      // or "yc:buy" when printing is locked (the server decides which).
      ..addJavaScriptChannel('YCApp', onMessageReceived: (m) => _onPageMessage(m.message))
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

  /// From the page's own button: "yc:buy" when locked, or the page to print. Only our pages can send
  /// it (navigation stays on /learn/ pages), and the server sends the print code only when unlocked.
  void _onPageMessage(String message) {
    if (message == 'yc:buy') {
      _buy();
    } else if (message.startsWith('<!doctype html>')) {
      _print(message);
    }
  }

  Future<void> _buy() async {
    final current = await _web.currentUrl();
    final slug = pageSlug(Uri.tryParse(current ?? '')) ?? widget.page.slug;
    if (!mounted) return;
    final page = slug == widget.page.slug
        ? widget.page
        : EducationPage(slug: slug, title: _title, kind: 'module', url: current ?? widget.page.url);
    if (await unlockPrinting(context, ref, page, widget.offer)) {
      await _web.reload(); // the server now unlocks this page
    }
  }

  Future<void> _print(String html) async {
    if (_printing) return;
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

class _PdfHandoutView extends ConsumerStatefulWidget {
  const _PdfHandoutView({required this.page, this.offer});

  final EducationPage page;
  final PrintOffer? offer;

  @override
  ConsumerState<_PdfHandoutView> createState() => _PdfHandoutViewState();
}

class _PdfHandoutViewState extends ConsumerState<_PdfHandoutView> {
  late Future<Uint8List> _bytes = _load();
  late bool _canPrint = widget.page.canPrint;

  Future<Uint8List> _load() async {
    final dio = Dio(
      BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60)),
    );
    final r = await dio.get<List<int>>(widget.page.url, options: Options(responseType: ResponseType.bytes));
    return Uint8List.fromList(r.data ?? const []);
  }

  Future<void> _buy() async {
    if (await unlockPrinting(context, ref, widget.page, widget.offer) && mounted) setState(() => _canPrint = true);
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
          // Here the app is the only gate: print and share (save) only when unlocked.
          return PdfPreview(
            key: ValueKey(_canPrint),
            build: (_) async => bytes,
            useActions: _canPrint,
            allowPrinting: _canPrint,
            allowSharing: _canPrint,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: widget.page.url.split('?').first.split('/').last,
          );
        },
      ),
      bottomNavigationBar: _canPrint
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _buy,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print / Save as PDF'),
                ),
              ),
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
