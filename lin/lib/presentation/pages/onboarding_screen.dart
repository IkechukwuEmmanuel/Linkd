import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../../presentation/providers/app_providers.dart';

/// Onboarding wizard for creating initial personas
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final linkeLinkedInUrlController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  String? selectedFilePath;
  String? _pitchPath;

  @override
  void dispose() {
    linkeLinkedInUrlController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingStateProvider);

    return PopScope(
      canPop: !onboardingState.isProcessing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create Your Personas'),
          automaticallyImplyLeading: !onboardingState.isProcessing,
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildStepContent(context, onboardingState),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(BuildContext context, OnboardingState state) {
    switch (state.step) {
      case OnboardingStep.chooseMethod:
        return _buildChooseMethodStep(context);
      case OnboardingStep.processing:
        return _buildProcessingStep(context, state);
      case OnboardingStep.confirmPersonas:
        return _buildConfirmPersonasStep(context, state);
      case OnboardingStep.complete:
        return _buildCompleteStep(context);
    }
  }

  Widget _buildChooseMethodStep(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.1),
        Icon(
          Icons.person_add,
          size: 80,
          color: AppTheme.primaryColor,
        ),
        const SizedBox(height: 32),
        Text(
          'Choose Your Onboarding Method',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        // Choice 1: Voice Pitch
        MethodCard(
          icon: Icons.mic,
          title: 'Voice Pitch',
          description: 'Record a 60-second professional pitch',
          onTap: () => _recordVoicePitch(context),
        ),
        const SizedBox(height: 16),
        // Choice 2: LinkedIn Profile
        MethodCard(
          icon: Icons.link,
          title: 'LinkedIn Profile',
          description: 'Import your LinkedIn profile URL',
          onTap: () => _showLinkedInDialog(context),
        ),
      ],
    );
  }

  void _showLinkedInDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter LinkedIn Profile URL'),
        content: TextField(
          controller: linkeLinkedInUrlController,
          decoration: const InputDecoration(
            hintText: 'https://linkedin.com/in/yourprofile',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = linkeLinkedInUrlController.text.trim();
              if (url.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid URL')),
                );
                return;
              }
              Navigator.pop(context);
              _processLinkedInProfile(url);
            },
            child: const Text('Process'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordVoicePitch(BuildContext context) async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Microphone access is required to record a voice pitch.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    bool isRecording = false;
    int elapsed = 0;
    Timer? timer;

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> start() async {
            final dir = await getTemporaryDirectory();
            _pitchPath =
                '${dir.path}/pitch_${DateTime.now().millisecondsSinceEpoch}.m4a';
            await _recorder.start(
              const RecordConfig(
                encoder: AudioEncoder.aacLc,
                bitRate: 32000,
                sampleRate: 16000,
                numChannels: 1,
              ),
              path: _pitchPath!,
            );
            elapsed = 0;
            timer = Timer.periodic(
                const Duration(seconds: 1),
                (_) => setSheetState(() => elapsed++));
            setSheetState(() => isRecording = true);
          }

          Future<void> stop() async {
            timer?.cancel();
            final path = await _recorder.stop();
            Navigator.pop(sheetContext);
            if (path != null) _processVoicePitch(path);
          }

          final mm = (elapsed ~/ 60).toString().padLeft(2, '0');
          final ss = (elapsed % 60).toString().padLeft(2, '0');

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isRecording ? 'Recording your pitch...' : 'Record your pitch',
                  style: Theme.of(sheetContext).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell us about your work, interests, and what you\'re looking for. Aim for ~60 seconds.',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Text('$mm:$ss',
                    style: Theme.of(sheetContext).textTheme.displaySmall),
                const SizedBox(height: 24),
                if (!isRecording)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Cancel'),
                      ),
                      FloatingActionButton.large(
                        heroTag: 'pitch-record',
                        backgroundColor: AppTheme.accentColor,
                        onPressed: start,
                        child: const Icon(Icons.mic,
                            color: Colors.white, size: 32),
                      ),
                    ],
                  )
                else
                  FloatingActionButton.large(
                    heroTag: 'pitch-stop',
                    backgroundColor: Colors.red,
                    onPressed: stop,
                    child: const Icon(Icons.stop, color: Colors.white),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
    timer?.cancel();
  }

  void _processVoicePitch(String filePath) async {
    ref.read(onboardingStateProvider.notifier).state = OnboardingState(
      step: OnboardingStep.processing,
      isProcessing: true,
      progress: 0,
    );

    try {
      final result = await ref.read(uploadVoicePitchProvider(filePath).future);
      final personasData = result['personas'] as List? ?? [];
      final personas = personasData
          .map((p) => Persona(
                id: p['id'] ?? 0,
                label: p['label'] ?? 'Unknown',
                weight: (p['weight'] ?? 1).toDouble(),
                confidenceScore: (p['confidence'] ?? 0.8).toDouble(),
                createdAt: DateTime.now(),
              ))
          .toList();

      if (mounted) {
        ref.read(onboardingStateProvider.notifier).state = OnboardingState(
          step: OnboardingStep.confirmPersonas,
          generatedPersonas: personas,
        );
      }
    } catch (e) {
      if (mounted) {
        ref.read(onboardingStateProvider.notifier).state = OnboardingState(
          step: OnboardingStep.chooseMethod,
          error: e.toString(),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      try {
        final f = File(filePath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  void _processLinkedInProfile(String url) async {
    ref.read(onboardingStateProvider.notifier).state = OnboardingState(
      step: OnboardingStep.processing,
      isProcessing: true,
      progress: 0,
    );

    try {
      final result = await ref.read(uploadLinkedInProfileProvider(url).future);
      // Convert personas map to Persona objects
      final personasData = result['personas'] as List? ?? [];
      final personas = personasData
          .map((p) => Persona(
            id: p['id'] ?? 0,
            label: p['label'] ?? 'Unknown',
            weight: (p['weight'] ?? 1).toDouble(),
            confidenceScore: (p['confidence'] ?? 0.8).toDouble(),
            createdAt: DateTime.now(),
          ))
          .toList();

      if (mounted) {
        ref.read(onboardingStateProvider.notifier).state = OnboardingState(
          step: OnboardingStep.confirmPersonas,
          generatedPersonas: personas,
        );
      }
    } catch (e) {
      if (mounted) {
        ref.read(onboardingStateProvider.notifier).state = OnboardingState(
          step: OnboardingStep.chooseMethod,
          error: e.toString(),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildProcessingStep(BuildContext context, OnboardingState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 32),
        Text(
          'Processing Your Profile...',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: state.progress / 100,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${state.progress}%',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _buildConfirmPersonasStep(BuildContext context, OnboardingState state) {
    final personas = state.generatedPersonas ?? [];
    return Column(
      children: [
        Icon(
          Icons.check_circle,
          size: 80,
          color: AppTheme.secondaryColor,
        ),
        const SizedBox(height: 24),
        Text(
          'Great! We found ${personas.length} personas',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Text(
          'Review and confirm your personas:',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        ...personas.map((p) => Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
              child: Text(
                p.label[0].toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(p.label),
            subtitle: Text('Weight: ${p.weight.toStringAsFixed(1)}/10'),
          ),
        )),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  ref.read(onboardingStateProvider.notifier).state = OnboardingState(
                    step: OnboardingStep.chooseMethod,
                  );
                },
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  ref.read(onboardingStateProvider.notifier).state = OnboardingState(
                    step: OnboardingStep.complete,
                  );
                },
                child: const Text('Confirm'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompleteStep(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.celebration,
          size: 100,
          color: AppTheme.secondaryColor,
        ),
        const SizedBox(height: 32),
        Text(
          'All Set!',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: AppTheme.secondaryColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Your personas are ready. Start recording interactions to discover more insights!',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppTheme.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go to Dashboard'),
          ),
        ),
      ],
    );
  }
}

class MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const MethodCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.borderColor, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: AppTheme.surfaceColor,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 48,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward,
              color: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
