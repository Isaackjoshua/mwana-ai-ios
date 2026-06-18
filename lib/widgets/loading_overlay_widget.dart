import 'package:flutter/material.dart';

/// Full-screen semi-transparent loading overlay with a message.
class LoadingOverlayWidget extends StatelessWidget {
  final String message;
  const LoadingOverlayWidget({super.key, this.message = 'Processing...'});

  @override
  Widget build(BuildContext context) {
    return Container(
      // ignore: deprecated_member_use
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
