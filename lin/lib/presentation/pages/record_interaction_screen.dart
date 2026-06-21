import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_providers.dart';
import '../providers/auth_provider.dart';
import 'contact_detail_page.dart';

enum _RecordPhase { idle, recording, processing, error }

/// Capture is the core verb of the app, so it gets a dark, weighted treatment —
/// a focus-mode surface that overrides the ambient light/dark theme (Section 9).
///
/// This screen only owns the visual framing; the recording → async ingest →
/// poll → navigate-to-contact pipeline (Section 10) is unchanged.
class RecordInteractionScreen extends ConsumerStatefulWidget {
  const RecordInteractionScreen({super.key});

  @override
  ConsumerState<RecordInteractionScreen> createState() =>
      _RecordInteractionScreenState();
}

class _RecordInteractionScreenState
    extends ConsumerState<RecordInteractionScreen> {
  // The capture surface is its own deliberately darker, more saturated
  // treatment — distinct from the dark-mode page background, used in BOTH
  // themes (a viewfinder/focus-mode exception to "respect system theme").
  static const Color _surface = Color(0xFF20231A);
  static const Color _cream = AppTheme.darkTextPrimary;
  static const Color _muted = AppTheme.darkTextSecondary;
  static const Color _moss = AppTheme.green400;

  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  int _secondsElapsed = 0;

  _RecordPhase _phase = _RecordPhase.idle;
  RecordingMode _mode = RecordingMode.recap;
  String _processingMessage = 'processing…';
  String _errorMessage = '';
  // When a denial is permanent, offer the system settings as the way out.
  bool _offerSettings = false;
  String? _recordingPath;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- timer ---

  void _startTimer() {
    _secondsElapsed = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  void _stopTimer() => _timer?.cancel();

  // ------------------------------------------------------------ recording ---

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _phase = _RecordPhase.error;
          _offerSettings = status.isPermanentlyDenied;
          _errorMessage =
              'linkd needs the microphone to capture a voice note about '
              'someone you met. nothing is recorded until you allow it.';
        });
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordingPath =
          '${dir.path}/linkd_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _recordingPath!,
      );

      if (!mounted) return;
      setState(() => _phase = _RecordPhase.recording);
      _startTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _RecordPhase.error;
          _offerSettings = false;
          _errorMessage = 'could not start recording: $e';
        });
      }
    }
  }

  Future<void> _cancelRecording() async {
    _stopTimer();
    try {
      await _recorder.stop();
    } catch (_) {}
    _deleteTempFile();
    if (mounted) {
      setState(() {
        _phase = _RecordPhase.idle;
        _secondsElapsed = 0;
      });
    }
  }

  Future<void> _stopAndProcess() async {
    _stopTimer();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      path = null;
    }

    if (path == null) {
      if (mounted) {
        setState(() {
          _phase = _RecordPhase.error;
          _offerSettings = false;
          _errorMessage = 'recording failed to save.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _phase = _RecordPhase.processing;
        _processingMessage = 'uploading…';
      });
    }
    await _uploadAndPoll(path);
  }

  // ----------------------------------------------------- upload + polling ---

  Future<void> _uploadAndPoll(String filePath) async {
    final apiClient = ref.read(apiClientProvider);
    final eventMode = ref.read(eventModeProvider);
    final eventName = eventMode.isActive ? eventMode.eventName : null;
    try {
      final jobId = await apiClient.ingestAudio(
        filePath: filePath,
        mode: _mode == RecordingMode.live ? 'live' : 'recap',
        durationSeconds: _secondsElapsed > 0 ? _secondsElapsed : 1,
        eventName: eventName,
      );
      if (eventMode.isActive) {
        ref.read(eventModeProvider.notifier).state = eventMode.copyWith(
          captureCount: eventMode.captureCount + 1,
        );
      }
      if (jobId == null) {
        throw Exception('no job id returned from server');
      }

      // Poll until the contact_id appears (the contact is created a moment
      // after transcription completes), or the job reports failure.
      Contact? contact;
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final status = await apiClient.pollIngestStatus(jobId);
        final s = (status['status'] as String?) ?? 'processing';
        if (mounted) setState(() => _processingMessage = _statusToMessage(s));

        final contactId = status['contact_id'];
        if (contactId is int) {
          contact = await apiClient.getContact(contactId);
          break;
        }
        if (s == 'failed') {
          throw Exception('processing failed on the server');
        }
      }

      if (!mounted) return;
      ref.invalidate(contactsProvider);
      ref.invalidate(upcomingFollowUpsProvider);

      if (contact != null) {
        final resolved = contact;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ContactDetailPage(contact: resolved),
          ),
        );
      } else {
        // Timed out while still processing — let the user move on; the
        // contact will surface in the list once the worker finishes.
        setState(() {
          _phase = _RecordPhase.idle;
          _secondsElapsed = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('still processing — your contact will appear shortly.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _RecordPhase.error;
          _offerSettings = false;
          _errorMessage = e.toString();
        });
      }
    } finally {
      _deleteTempFile(path: filePath);
    }
  }

  String _statusToMessage(String status) {
    switch (status) {
      case 'processing':
      case 'uploaded':
        return 'transcribing your note…';
      case 'completed':
        return 'building their profile…';
      case 'failed':
        return 'something went wrong';
      default:
        return 'processing…';
    }
  }

  void _deleteTempFile({String? path}) {
    final target = path ?? _recordingPath;
    if (target == null) return;
    try {
      final f = File(target);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // ------------------------------------------------------------------ UI ---

  @override
  Widget build(BuildContext context) {
    // Override the ambient theme: this screen is always a dark focus surface.
    return Theme(
      data: AppTheme.darkTheme().copyWith(
        scaffoldBackgroundColor: _surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: _surface,
          foregroundColor: _cream,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      child: Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close, color: _cream),
            onPressed: _phase == _RecordPhase.processing
                ? null
                : () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _buildPhase(context),
          ),
        ),
      ),
    );
  }

  Widget _buildPhase(BuildContext context) {
    switch (_phase) {
      case _RecordPhase.processing:
        return _processingView(context);
      case _RecordPhase.error:
        return _errorView(context);
      case _RecordPhase.idle:
      case _RecordPhase.recording:
        return _captureView(context);
    }
  }

  // The main idle/recording surface.
  Widget _captureView(BuildContext context) {
    final recording = _phase == _RecordPhase.recording;
    final serif = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'ready when you are',
          style: serif.displayLarge?.copyWith(color: _cream),
        ),
        const SizedBox(height: 10),
        Text(
          recording
              ? 'listening — take your time.'
              : 'choose how you\'re capturing this.',
          style: serif.bodyLarge?.copyWith(color: _muted),
        ),
        const SizedBox(height: 36),
        if (!recording) _modeCards(context),
        const Spacer(),
        Center(child: _micButton(context, recording)),
        const SizedBox(height: 28),
        Center(
          child: Text(
            _formatDuration(_secondsElapsed),
            style: serif.displayMedium?.copyWith(color: _cream),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            recording
                ? 'tap to finish whenever you\'re ready'
                : 'tap the mic to start',
            style: serif.bodySmall?.copyWith(color: _muted),
          ),
        ),
        if (recording) ...[
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _cancelRecording,
              child: Text('cancel',
                  style: serif.labelLarge?.copyWith(color: _muted)),
            ),
          ),
        ],
        const Spacer(),
      ],
    );
  }

  Widget _modeCards(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _modeCard(
            context,
            mode: RecordingMode.recap,
            title: 'recap',
            subtitle: 'tell me about them, after',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _modeCard(
            context,
            mode: RecordingMode.live,
            title: 'live',
            subtitle: 'capture the conversation now',
          ),
        ),
      ],
    );
  }

  Widget _modeCard(
    BuildContext context, {
    required RecordingMode mode,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == mode;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _moss : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _moss : _muted.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineMedium?.copyWith(color: _cream),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected
                    ? _cream.withValues(alpha: 0.85)
                    : _muted,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _micButton(BuildContext context, bool recording) {
    return GestureDetector(
      onTap: recording ? _stopAndProcess : _startRecording,
      child: Container(
        width: 116,
        height: 116,
        decoration: BoxDecoration(
          color: recording ? AppTheme.red400 : _moss,
          shape: BoxShape.circle,
        ),
        child: Icon(
          recording ? Icons.stop_rounded : Icons.mic,
          color: _cream,
          size: 44,
        ),
      ),
    );
  }

  Widget _processingView(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: _moss),
          const SizedBox(height: 28),
          Text(
            _processingMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(color: _cream),
          ),
        ],
      ),
    );
  }

  Widget _errorView(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('hold on', style: theme.textTheme.displayMedium?.copyWith(color: _cream)),
        const SizedBox(height: 14),
        Text(
          _errorMessage,
          style: theme.textTheme.bodyLarge?.copyWith(color: _muted, height: 1.5),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _phase = _RecordPhase.idle;
                _secondsElapsed = 0;
                _offerSettings = false;
              }),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('try again',
                      style: theme.textTheme.headlineLarge
                          ?.copyWith(color: AppTheme.green200)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward,
                      color: AppTheme.green200, size: 22),
                ],
              ),
            ),
            if (_offerSettings) ...[
              const SizedBox(width: 24),
              GestureDetector(
                onTap: openAppSettings,
                child: Text('open settings',
                    style: theme.textTheme.bodyLarge?.copyWith(color: _muted)),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
