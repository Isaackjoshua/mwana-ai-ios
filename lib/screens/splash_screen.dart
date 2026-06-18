import 'package:flutter/material.dart';
import '../services/model_manager_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final ready = await ModelManagerService().isInstalled();
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      ready ? '/input' : '/model-setup',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icons/app_icon.png', width: 100, height: 100),
            const SizedBox(height: 16),
            Text('Mwana-AI', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            const Text('AI-Assisted Breast Ultrasound Analysis'),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
