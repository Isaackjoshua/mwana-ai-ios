import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'models/inference_result.dart';
import 'models/report_result.dart';
import 'screens/splash_screen.dart';
import 'screens/model_setup_screen.dart';
import 'screens/input_selection_screen.dart';
import 'screens/image_confirm_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/report_screen.dart';
import 'screens/export_screen.dart';
import 'screens/probe_connect_screen.dart';
import 'screens/probe_imaging_screen.dart';
import 'screens/multi_analysis_screen.dart';
import 'screens/cumulative_report_screen.dart';
import 'models/section_analysis.dart';
import 'services/butterfly_probe_service.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mwana-AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B4F72),
        useMaterial3: true,
      ),
      initialRoute: '/splash',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/splash':
            return MaterialPageRoute(builder: (_) => const SplashScreen());
          case '/model-setup':
            return MaterialPageRoute(builder: (_) => const ModelSetupScreen());
          case '/input':
            return MaterialPageRoute(builder: (_) => const InputSelectionScreen());
          case '/confirm':
            final imagePath = settings.arguments as String? ?? '';
            return MaterialPageRoute(
              builder: (_) => ImageConfirmScreen(imagePath: imagePath),
            );
          case '/analysis':
            final imagePath = settings.arguments as String? ?? '';
            return MaterialPageRoute(
              builder: (_) => AnalysisScreen(imagePath: imagePath),
            );
          case '/report':
            final args = settings.arguments as Map<String, dynamic>?;
            final inferenceResult = args?['inferenceResult'] as InferenceResult?;
            if (inferenceResult == null) {
              return MaterialPageRoute(builder: (_) => const SplashScreen());
            }
            return MaterialPageRoute(
              builder: (_) => ReportScreen(
                inferenceResult: inferenceResult,
                overlayBytes: args?['overlayBytes'] as Uint8List?,
              ),
            );
          case '/export':
            final args = settings.arguments as Map<String, dynamic>?;
            final inferenceResult = args?['inferenceResult'] as InferenceResult?;
            final reportResult = args?['reportResult'] as ReportResult?;
            if (inferenceResult == null || reportResult == null) {
              return MaterialPageRoute(builder: (_) => const SplashScreen());
            }
            return MaterialPageRoute(
              builder: (_) => ExportScreen(
                inferenceResult: inferenceResult,
                reportResult: reportResult,
                overlayBytes: args?['overlayBytes'] as Uint8List?,
              ),
            );
          case '/probe-connect':
            return MaterialPageRoute(builder: (_) => const ProbeConnectScreen());
          case '/probe-imaging':
            final service = settings.arguments as ButterflyProbeService?;
            if (service == null) {
              return MaterialPageRoute(builder: (_) => const SplashScreen());
            }
            return MaterialPageRoute(
              builder: (_) => ProbeImagingScreen(service: service),
            );
          case '/multi-analysis':
            final paths = settings.arguments as List<String>?;
            if (paths == null || paths.isEmpty) {
              return MaterialPageRoute(builder: (_) => const SplashScreen());
            }
            return MaterialPageRoute(
              builder: (_) => MultiAnalysisScreen(imagePaths: paths),
            );
          case '/cumulative-report':
            final sections = settings.arguments as List<SectionAnalysis>?;
            if (sections == null || sections.isEmpty) {
              return MaterialPageRoute(builder: (_) => const SplashScreen());
            }
            return MaterialPageRoute(
              builder: (_) => CumulativeReportScreen(sections: sections),
            );
          default:
            return MaterialPageRoute(builder: (_) => const SplashScreen());
        }
      },
    );
  }
}
