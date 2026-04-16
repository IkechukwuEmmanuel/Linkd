import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../pages/home_page.dart';
import '../pages/personas_screen.dart';
import '../pages/metrics_screen.dart';
import '../pages/settings_screen.dart';
import '../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';

/// Main navigation shell with bottom navigation and central record button
class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key});

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  int _selectedIndex = 0;
  Timer? _recordingTimer;

  static const List<Widget> _screens = [
    HomePage(),
    PersonasScreen(), // Networks
    MetricsScreen(), // Insights
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    // Prevent selecting the record button (index 2 is reserved for the central button)
    if (index != 2) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _startRecordingTimer(WidgetRef ref) {
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

  void _handleRecordButtonPressed(WidgetRef ref) {
    final state = ref.read(recordingStateProvider);
    
    if (!state.isRecording) {
      // Start recording
      ref.read(recordingStateProvider.notifier).state = state.copyWith(
        isRecording: true,
        isPaused: false,
        duration: Duration.zero,
      );
      _startRecordingTimer(ref);
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
      _startRecordingTimer(ref);
    }
  }

  void _handleRecordButtonDoublePressed(WidgetRef ref) {
    final state = ref.read(recordingStateProvider);
    
    if (state.isRecording) {
      // Stop recording
      _stopRecordingTimer();
      ref.read(recordingStateProvider.notifier).state = state.copyWith(
        isRecording: false,
        isPaused: false,
      );
      // Process the recording
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
    _recordingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(recordingStateProvider);

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Bottom navigation bar background
            BottomNavigationBar(
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.language), // Cone icon for networks
                  label: 'Networks',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.monitor), // Placeholder for central button
                  label: '',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.insights),
                  label: 'Insights',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
              currentIndex: _selectedIndex > 2 ? 3 : (_selectedIndex == 2 ? 0 : _selectedIndex),
              onTap: (index) {
                if (index >= 2) {
                  _onItemTapped(index + 1);
                } else {
                  _onItemTapped(index);
                }
              },
              type: BottomNavigationBarType.fixed,
              elevation: 0,
            ),
            // Central record button
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Center(
                child: GestureDetector(
                  onTap: () => _handleRecordButtonPressed(ref),
                  onDoubleTap: () => _handleRecordButtonDoublePressed(ref),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: recordingState.isRecording
                            ? Colors.red
                            : AppTheme.primaryColor,
                        boxShadow: [
                          BoxShadow(
                            color: (recordingState.isRecording
                                    ? Colors.red
                                    : AppTheme.primaryColor)
                                .withValues(alpha: 0.6),
                            blurRadius: 12,
                            spreadRadius: recordingState.isRecording ? 2 : 0,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            recordingState.isPaused
                                ? Icons.play_arrow
                                : Icons.fiber_manual_record,
                            color: Colors.white,
                            size: 28,
                          ),
                          if (recordingState.isRecording)
                            Text(
                              _formatDuration(recordingState.duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
