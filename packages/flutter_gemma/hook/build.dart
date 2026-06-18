// Compatibility shim — supports both Flutter 3.24.5 (out_dir) and Flutter 3.44+ (out_file).
//
// Writes an empty output so the native_assets_builder framework is satisfied.
// On-device inference is bundled via the platform build system (Gradle / CocoaPods),
// not via native assets.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final configPath = args
      .firstWhere((a) => a.startsWith('--config='), orElse: () => '')
      .replaceFirst('--config=', '');

  if (configPath.isEmpty) {
    stderr.writeln('flutter_gemma hook: no --config argument, exiting.');
    exit(1);
  }

  final configJson =
      jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;

  final timestamp = DateTime.now().toUtc().toIso8601String();
  final emptyOutput = JsonEncoder.withIndent('  ').convert({
    'timestamp': timestamp,
    'version': '1.3.0',
    'assets': [],
    'assetsForLinking': {},
  });

  // Flutter 3.44+ protocol: write to out_file directly.
  final outFile = (configJson['out_file'] as String?) ?? '';
  if (outFile.isNotEmpty) {
    final f = File(outFile);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(emptyOutput);
    stdout.writeln('flutter_gemma hook: wrote empty output to out_file');
    return;
  }

  // Flutter 3.24.x protocol: write to out_dir/build_output.json.
  final outDir = (configJson['out_dir'] as String?) ?? '';
  if (outDir.isNotEmpty) {
    Directory(outDir).createSync(recursive: true);
    File('${outDir}build_output.json').writeAsStringSync(emptyOutput);
    stdout.writeln('flutter_gemma hook: wrote empty build_output.json');
    return;
  }

  stderr.writeln('flutter_gemma hook: neither out_file nor out_dir found in config.');
  exit(1);
}
