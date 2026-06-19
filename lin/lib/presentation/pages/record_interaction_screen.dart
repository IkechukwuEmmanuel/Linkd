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

/// Records an interaction, uploads it to the async ingest pipeline, polls for
/// the resulting Contact, and navigates to its detail page.
class RecordInteractionScreen extends ConsumerStatefulWidget {
  const RecordInteractionScreen({super.key});

  @override
  ConsumerState<RecordInteractionScreen> createState() =>
      _RecordInteractionScreenState();
}

class _RecordInteractionScreenState
    extends ConsumerState<RecordInteractionScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _eventController = TextEditingController();
  Timer? _timer;
  int _secondsElapsed = 0;

  _RecordPhase _phase = _RecordPhase.idle;
  RecordingMode _mode = RecordingMode.recap;
  String? _recordingPath;
  String _processingMessage = 'Processing...';
  String _errorMessage = '';

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _eventController.dispose();
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
      if (mounted) _showPermissionDeniedDialog();
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
          _errorMessage = 'Could not start recording: $e';
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
          _errorMessage = 'Recording failed to save.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _phase = _RecordPhase.processing;
        _processingMessage = 'Uploading...';
      });
    }
    await _uploadAndPoll(path);
  }

  // ----------------------------------------------------- upload + polling ---

  Future<void> _uploadAndPoll(String filePath) async {
    final apiClient = ref.read(apiClientProvider);
    final eventMode = ref.read(eventModeProvider);
    final eventName = eventMode.isActive
        ? eventMode.eventName
        : (_eventController.text.trim().isEmpty
            ? null
            : _eventController.text.trim());
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
        throw Exception('No job ID returned from server');
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
          throw Exception('Processing failed on the server');
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
            content: Text(
              'Still processing — your contact will appear shortly.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _RecordPhase.error;
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
        return 'Transcribing your note...';
      case 'completed':
        return 'Building contact profile...';
      case 'failed':
        return 'Something went wrong';
      default:
        return 'Processing...';
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

  // --------------------------------------------------------------- dialogs ---

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Microphone access needed'),
        content: const Text(
          'Linkd needs microphone access to capture voice notes about people '
          'you meet. Enable it in Settings to record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record Interaction')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              _buildVisual(context),
              const SizedBox(height: 40),
              if (_phase != _RecordPhase.processing)
                Text(
                  _formatDuration(_secondsElapsed),
                  style: Theme.of(context).textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 24),
              _buildBody(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _RecordPhase.idle:
        return Column(
          children: [
            _buildEventField(context),
            const SizedBox(height: 20),
            _buildModeSelector(context),
            const SizedBox(height: 32),
            FloatingActionButton.large(
              heroTag: 'record',
              backgroundColor: AppTheme.accentColor,
              onPressed: _startRecording,
              child: const Icon(Icons.mic, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap to start recording',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case _RecordPhase.recording:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FloatingActionButton(
              heroTag: 'cancel',
              backgroundColor: Colors.grey,
              onPressed: _cancelRecording,
              child: const Icon(Icons.close),
            ),
            FloatingActionButton.large(
              heroTag: 'stop',
              backgroundColor: Colors.red,
              onPressed: _stopAndProcess,
              child: const Icon(Icons.stop, color: Colors.white),
            ),
          ],
        );
      case _RecordPhase.processing:
        return Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _processingMessage,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        );
      case _RecordPhase.error:
        return Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => setState(() {
                _phase = _RecordPhase.idle;
                _secondsElapsed = 0;
              }),
              child: const Text('Try Again'),
            ),
          ],
        );
    }
  }

  Widget _buildVisual(BuildContext context) {
    final recording = _phase == _RecordPhase.recording;
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: recording
            ? Colors.red.withValues(alpha: 0.08)
            : AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: recording ? Colors.red : AppTheme.borderColor,
          width: recording ? 2 : 1,
        ),
      ),
      child: Center(
        child: recording
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic, color: Colors.red, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Recording...',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  30,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      width: 4,
                      height: 20 + (index % 15).toDouble() * 4,
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEventField(BuildContext context) {
    final eventMode = ref.watch(eventModeProvider);
    if (eventMode.isActive) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.event, size: 18, color: AppTheme.accentColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Event: ${eventMode.eventName}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppTheme.accentColor),
              ),
            ),
          ],
        ),
      );
    }
    return TextField(
      controller: _eventController,
      decoration: const InputDecoration(
        labelText: 'Event (optional)',
        hintText: 'Where did you meet them?',
        prefixIcon: Icon(Icons.event),
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Interaction Mode',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('LIVE'),
                  selected: _mode == RecordingMode.live,
                  onSelected: (sel) {
                    if (sel) setState(() => _mode = RecordingMode.live);
                  },
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('RECAP'),
                  selected: _mode == RecordingMode.recap,
                  onSelected: (sel) {
                    if (sel) setState(() => _mode = RecordingMode.recap);
                  },
                ),
              ),
            ),
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
