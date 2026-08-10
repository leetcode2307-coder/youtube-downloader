import 'dart:async';
import 'package:flutter/material.dart';

import '../models/download_item.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/history_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  final _urlController = TextEditingController();

  List<DownloadItem> _history = [];
  bool _historyLoading = true;

  JobState _jobState = JobState.idle;
  String? _statusMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    try {
      final items = await _api.getHistory();
      setState(() => _history = items);
    } catch (_) {
      // Silently keep whatever we had; pull-to-refresh lets the user retry.
    } finally {
      setState(() => _historyLoading = false);
    }
  }

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showSnack('Paste a YouTube URL first');
      return;
    }

    setState(() {
      _jobState = JobState.queued;
      _statusMessage = 'Starting…';
    });

    try {
      final jobId = await _api.startDownload(url);
      _pollJob(jobId);
    } on ApiException catch (e) {
      setState(() {
        _jobState = JobState.failed;
        _statusMessage = e.message;
      });
      await NotificationService.instance.notifyFailed(e.message);
    } catch (_) {
      setState(() {
        _jobState = JobState.failed;
        _statusMessage = 'Could not reach the server';
      });
      await NotificationService.instance.notifyPaused('Could not reach the server');
    }
  }

  void _pollJob(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await _api.getStatus(jobId);
        if (!mounted) return;

        switch (status.state) {
          case JobState.downloading:
          case JobState.queued:
            setState(() {
              _jobState = status.state;
              _statusMessage = 'Downloading…';
            });
            break;
          case JobState.completed:
            timer.cancel();
            setState(() {
              _jobState = JobState.completed;
              _statusMessage = 'Completed: ${status.filename}';
            });
            _urlController.clear();
            await NotificationService.instance
                .notifyCompleted(status.filename ?? 'video.mp4');
            await _loadHistory();
            break;
          case JobState.failed:
            timer.cancel();
            setState(() {
              _jobState = JobState.failed;
              _statusMessage = status.error ?? 'Download failed';
            });
            await NotificationService.instance
                .notifyPaused(status.error ?? 'Download failed');
            break;
          case JobState.idle:
            break;
        }
      } catch (_) {
        timer.cancel();
        if (!mounted) return;
        setState(() {
          _jobState = JobState.failed;
          _statusMessage = 'Lost connection to server';
        });
        await NotificationService.instance.notifyPaused('Lost connection to server');
      }
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  bool get _isBusy =>
      _jobState == JobState.queued || _jobState == JobState.downloading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHistory,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YouTube Downloader',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Paste a link, we\'ll do the rest.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildInputCard(theme),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 14),
                        _buildStatusBanner(theme),
                      ],
                      const SizedBox(height: 28),
                      Text(
                        'Download History',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_historyLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_history.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No downloads yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => HistoryCard(item: _history[index]),
                    childCount: _history.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _urlController,
            enabled: !_isBusy,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Paste YouTube URL…',
              prefixIcon: const Icon(Icons.link_rounded),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _startDownload,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_isBusy ? 'Downloading…' : 'Download'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(ThemeData theme) {
    Color bg;
    Color fg;
    IconData icon;

    switch (_jobState) {
      case JobState.completed:
        bg = theme.colorScheme.primaryContainer;
        fg = theme.colorScheme.onPrimaryContainer;
        icon = Icons.check_circle_rounded;
        break;
      case JobState.failed:
        bg = theme.colorScheme.errorContainer;
        fg = theme.colorScheme.onErrorContainer;
        icon = Icons.error_rounded;
        break;
      default:
        bg = theme.colorScheme.secondaryContainer;
        fg = theme.colorScheme.onSecondaryContainer;
        icon = Icons.hourglass_top_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
