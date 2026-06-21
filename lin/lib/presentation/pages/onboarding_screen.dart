import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/entities.dart';
import '../../presentation/providers/app_providers.dart';
import '../widgets/facet_ring.dart';
import 'personas_screen.dart';

/// Onboarding — typography-led entry into building the user's facets.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final linkeLinkedInUrlController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  String? _pitchPath;
  late final TapGestureRecognizer _speakTap;
  late final TapGestureRecognizer _importTap;

  @override
  void initState() {
    super.initState();
    _speakTap = TapGestureRecognizer()..onTap = _recordVoicePitch;
    _importTap = TapGestureRecognizer()
      ..onTap = () => _showLinkedInDialog(context);
  }

  @override
  void dispose() {
    linkeLinkedInUrlController.dispose();
    _recorder.dispose();
    _speakTap.dispose();
    _importTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingStateProvider);

    return PopScope(
      canPop: !onboardingState.isProcessing,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !onboardingState.isProcessing,
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(28),
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
    final tokens = MossTokens.of(context);
    final theme = Theme.of(context);
    final base = theme.textTheme.displayMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.12),
        Text('let\'s build your profile', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 28),
        Text.rich(
          TextSpan(
            style: base,
            children: [
              const TextSpan(text: 'would you rather '),
              TextSpan(
                text: 'speak',
                recognizer: _speakTap,
                style: base?.copyWith(
                  color: tokens.tierStrong,
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.green100,
                  decorationThickness: 3,
                ),
              ),
              const TextSpan(text: ' it, or '),
              TextSpan(
                text: 'import',
                recognizer: _importTap,
                style: base?.copyWith(
                  color: tokens.tierModerate,
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.amber100,
                  decorationThickness: 3,
                ),
              ),
              const TextSpan(text: ' it?'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'speak a short pitch about your work and interests, or import your linkedin profile.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  void _showLinkedInDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('import linkedin'),
        content: TextField(
          controller: linkeLinkedInUrlController,
          decoration: const InputDecoration(
            hintText: 'https://linkedin.com/in/you',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = linkeLinkedInUrlController.text.trim();
              if (url.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('please enter a valid url')),
                );
                return;
              }
              Navigator.pop(context);
              _processLinkedInProfile(url);
            },
            child: const Text('import'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordVoicePitch() async {
    final messenger = ScaffoldMessenger.of(context);
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('microphone access is required to record a voice pitch.'),
        ),
      );
      return;
    }

    bool isRecording = false;
    int elapsed = 0;
    Timer? timer;

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        final tokens = MossTokens.of(sheetContext);
        return StatefulBuilder(
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
              if (sheetContext.mounted) Navigator.pop(sheetContext);
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
                    isRecording ? 'recording your pitch' : 'record your pitch',
                    style: Theme.of(sheetContext).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'tell us about your work, interests, and what you\'re looking for. aim for ~60 seconds.',
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
                          child: const Text('cancel'),
                        ),
                        FloatingActionButton.large(
                          heroTag: 'pitch-record',
                          backgroundColor: tokens.tierStrong,
                          foregroundColor:
                              Theme.of(sheetContext).colorScheme.onPrimary,
                          onPressed: start,
                          child: const Icon(Icons.mic, size: 32),
                        ),
                      ],
                    )
                  else
                    FloatingActionButton.large(
                      heroTag: 'pitch-stop',
                      backgroundColor: tokens.danger,
                      foregroundColor: AppTheme.darkTextPrimary,
                      onPressed: stop,
                      child: const Icon(Icons.stop),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
    timer?.cancel();
  }

  void _processVoicePitch(String filePath) async {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(onboardingStateProvider.notifier).state = OnboardingState(
      step: OnboardingStep.processing,
      isProcessing: true,
      progress: 0,
    );

    try {
      final result = await ref.read(uploadVoicePitchProvider(filePath).future);
      final personas = _parsePersonas(result);
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
        messenger.showSnackBar(SnackBar(content: Text('error: $e')));
      }
    } finally {
      try {
        final f = File(filePath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  void _processLinkedInProfile(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(onboardingStateProvider.notifier).state = OnboardingState(
      step: OnboardingStep.processing,
      isProcessing: true,
      progress: 0,
    );

    try {
      final result = await ref.read(uploadLinkedInProfileProvider(url).future);
      final personas = _parsePersonas(result);
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
        messenger.showSnackBar(SnackBar(content: Text('error: $e')));
      }
    }
  }

  List<Persona> _parsePersonas(Map<String, dynamic> result) {
    final personasData = result['personas'] as List? ?? [];
    return personasData
        .map((p) => Persona(
              id: p['id'] ?? 0,
              label: p['label'] ?? 'unknown',
              weight: (p['weight'] ?? 1).toDouble(),
              confidenceScore: (p['confidence'] ?? 0.8).toDouble(),
              createdAt: DateTime.now(),
            ))
        .toList();
  }

  Widget _buildProcessingStep(BuildContext context, OnboardingState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 32),
        Center(
          child: Text('reading your profile',
              style: Theme.of(context).textTheme.headlineMedium),
        ),
      ],
    );
  }

  Widget _buildConfirmPersonasStep(BuildContext context, OnboardingState state) {
    final personas = state.generatedPersonas ?? [];
    final tokens = MossTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('we found ${personas.length} facets',
            style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text('these are the facets of how you show up. confirm them later.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: tokens.textSecondary)),
        const SizedBox(height: 24),
        ...personas.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  FacetRing(
                    strength: facetStrength(p),
                    tier: facetTier(p),
                    size: 44,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(p.label,
                        style: Theme.of(context).textTheme.headlineLarge),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              ref.read(onboardingStateProvider.notifier).state =
                  OnboardingState(step: OnboardingStep.complete);
            },
            child: const Text('looks right, continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildCompleteStep(BuildContext context) {
    final tokens = MossTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Text('you\'re all set', style: Theme.of(context).textTheme.displayLarge),
        const SizedBox(height: 16),
        Text(
          'your facets are ready. start capturing the people you meet, and linkd will find where you overlap.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('go to linkd'),
          ),
        ),
      ],
    );
  }
}
