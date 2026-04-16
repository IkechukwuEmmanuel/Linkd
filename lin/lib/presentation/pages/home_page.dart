import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../presentation/providers/app_providers.dart';

/// Dashboard/Home screen - main hub for the app
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Timer? _recordingTimer;

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final state = ref.read(recordingStateProvider);
      if (state.isRecording && !state.isPaused) {
        ref.read(recordingStateProvider.notifier).state = state.copyWith(
          duration: state.duration + const Duration(milliseconds: 100),
        );
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  void _handleRecordButtonPressed() {
    final state = ref.read(recordingStateProvider);

    if (!state.isRecording) {
      // Start recording
      ref.read(recordingStateProvider.notifier).state = state.copyWith(
        isRecording: true,
        isPaused: false,
        duration: Duration.zero,
      );
      _startRecordingTimer();
    } else if (!state.isPaused) {
      // Pause recording
      ref.read(recordingStateProvider.notifier).state = state.copyWith(
        isPaused: true,
      );
    } else {
      // Resume recording
      ref.read(recordingStateProvider.notifier).state = state.copyWith(
        isPaused: false,
      );
      _startRecordingTimer();
    }
  }

  void _handleRecordButtonDoublePressed() {
    final state = ref.read(recordingStateProvider);

    if (state.isRecording) {
      // Stop recording
      _stopRecordingTimer();
      ref.read(recordingStateProvider.notifier).state = state.copyWith(
        isRecording: false,
        isPaused: false,
      );
      // Show recording results
      _showRecordingResults(state.duration);
    }
  }

  void _showRecordingResults(Duration duration) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Recording stopped. Duration: ${duration.inSeconds}s'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _stopRecordingTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final personasAsync = ref.watch(personasProvider);
    final recordingState = ref.watch(recordingStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linkd'),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Show info
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Welcome section
            if (user != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Welcome back, ${user.email.split('@')[0]}',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 40),

            // BIG RECORD BUTTON IN THE MIDDLE
            GestureDetector(
              onTap: _handleRecordButtonPressed,
              onDoubleTap: _handleRecordButtonDoublePressed,
              child: Center(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: recordingState.isRecording ? Colors.red : AppTheme.primaryColor,
                    boxShadow: [
                      BoxShadow(
                        color: (recordingState.isRecording ? Colors.red : AppTheme.primaryColor)
                            .withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: recordingState.isRecording ? 4 : 2,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Animated pulse ring
                      if (recordingState.isRecording)
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                        ),
                      // Main button content
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            recordingState.isPaused ? Icons.play_arrow : Icons.fiber_manual_record,
                            color: Colors.white,
                            size: 56,
                          ),
                          const SizedBox(height: 12),
                          if (recordingState.isRecording)
                            Column(
                              children: [
                                Text(
                                  _formatDuration(recordingState.duration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  recordingState.isPaused ? 'Paused' : 'Recording',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          else
                            const Text(
                              'Start Recording',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Recording instructions
            if (!recordingState.isRecording)
              Center(
                child: Text(
                  'Tap to start • Tap again to pause • Double tap to stop',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              )
            else
              Center(
                child: Text(
                  recordingState.isPaused ? 'Paused - Tap to resume' : 'Recording...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: recordingState.isPaused ? Colors.orange : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            const SizedBox(height: 40),

            // Recent Networks / Recordings Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Networks',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  personasAsync.when(
                    data: (personas) {
                      if (personas.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.borderColor.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'No networks yet. Start recording to build your network!',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: personas.length,
                        itemBuilder: (context, index) {
                          final persona = personas[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.borderColor.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                                  child: Icon(
                                    Icons.person,
                                    color: AppTheme.primaryColor,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        persona.label,
                                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.scale,
                                            size: 14,
                                            color: AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Weight: ${persona.weight.toStringAsFixed(1)}/10',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Icon(
                                            Icons.show_chart,
                                            size: 14,
                                            color: AppTheme.secondaryColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Confidence: ${((persona.confidenceScore ?? 0) * 100).toStringAsFixed(0)}%',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: AppTheme.secondaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    loading: () => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    error: (err, _) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Error loading networks: $err'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
