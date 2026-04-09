import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

// @Native resolves bundled assets by package URI, which omits the leading lib/.
const _ghosttyAssetName = 'src/ghostty_bindings.g.dart';
const _ptyAssetName = 'src/pty_ffi.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final codeConfig = input.config.code;
    final targetOS = codeConfig.targetOS;
    if (targetOS != OS.macOS) {
      return;
    }

    final targetArch = codeConfig.targetArchitecture;
    final targetArchName = switch (targetArch) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x64',
      _ => throw UnsupportedError(
        'Unsupported macOS architecture for native deps: ${targetArch.name}',
      ),
    };

    final packageRoot = Directory.fromUri(input.packageRoot).path;
    final buildScript = File.fromUri(
      input.packageRoot.resolve('scripts/build_native_deps.sh'),
    );
    if (!buildScript.existsSync()) {
      throw StateError('Missing build script: ${buildScript.path}');
    }

    final outDir = Directory.fromUri(
      input.outputDirectory.resolve('native/$targetArchName/'),
    );
    outDir.createSync(recursive: true);

    final macOSMinVersion = codeConfig.macOS.targetVersion;
    final processArgs = [
      'bash',
      buildScript.path,
      '--target-os',
      'macos',
      '--target-arch',
      targetArchName,
      '--out-dir',
      outDir.path,
      '--macos-min-version',
      '$macOSMinVersion',
    ];
    final process = await Process.start(
      '/usr/bin/env',
      processArgs,
      workingDirectory: packageRoot,
    );

    await stdout.addStream(process.stdout);
    await stderr.addStream(process.stderr);
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw ProcessException(
        '/usr/bin/env',
        processArgs,
        'Native build failed for macOS/$targetArchName',
        exitCode,
      );
    }

    final ghosttyLib = File.fromUri(outDir.uri.resolve('libghostty-vt.dylib'));
    final ptyLib = File.fromUri(outDir.uri.resolve('libpty.dylib'));
    if (!ghosttyLib.existsSync()) {
      throw StateError('Expected output missing: ${ghosttyLib.path}');
    }
    if (!ptyLib.existsSync()) {
      throw StateError('Expected output missing: ${ptyLib.path}');
    }

    output.dependencies.add(buildScript.uri);
    output.dependencies.add(input.packageRoot.resolve('native/pty.c'));

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _ghosttyAssetName,
        file: ghosttyLib.uri,
        linkMode: DynamicLoadingBundled(),
      ),
    );

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _ptyAssetName,
        file: ptyLib.uri,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}
