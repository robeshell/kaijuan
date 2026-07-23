import 'dart:io';

const _knownPlatforms = {'android', 'ios', 'macos', 'windows'};
const _artifactPrefix = 'kaijuan';
const _macosAppCandidates = [
  'build/macos/Build/Products/Release/开卷.app',
  'build/macos/Build/Products/Release/Kaika.app',
  'build/macos/Build/Products/Release/kaijuan.app',
];
const _windowsIss = 'packaging/windows/kaijuan.iss';
const _publisher = 'com.kaijuan.reader';

Future<void> main(List<String> arguments) async {
  final options = _ReleaseOptions.parse(arguments);
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('Run this command from the kaijuan repository root.');
    exitCode = 64;
    return;
  }

  final originalPubspec = await pubspec.readAsString();
  final current = _ReleaseVersion.read(originalPubspec);
  final release = options.bump ? current.nextPatch() : current;
  final platforms = options.platforms.isEmpty
      ? _defaultPlatformsForHost()
      : options.platforms;
  _validatePlatforms(platforms);

  stdout.writeln(
    '开卷 ${current.name} → ${release.name} '
    '(internal build ${release.buildNumber})',
  );
  stdout.writeln('Platforms: ${platforms.join(', ')}');
  if (options.dryRun) return;

  if (options.bump) {
    await pubspec.writeAsString(release.applyTo(originalPubspec));
  }

  try {
    final dist = Directory('dist');
    await dist.create(recursive: true);
    for (final platform in platforms) {
      await _buildPlatform(platform, release, dist, options);
    }
  } catch (_) {
    if (options.bump) await pubspec.writeAsString(originalPubspec);
    stderr.writeln(
      'Release failed; pubspec.yaml was restored to ${current.name}.',
    );
    rethrow;
  }

  stdout.writeln('Release ${release.name} completed. Artifacts are in dist/.');
}

class _ReleaseOptions {
  const _ReleaseOptions({
    required this.bump,
    required this.dryRun,
    required this.platforms,
    required this.skipMsix,
    required this.skipSetup,
    required this.skipCodegen,
  });

  factory _ReleaseOptions.parse(List<String> arguments) {
    var bump = true;
    var dryRun = false;
    var skipMsix = false;
    var skipSetup = false;
    var skipCodegen = false;
    final platforms = <String>[];
    for (final argument in arguments) {
      switch (argument) {
        case '--no-bump':
          bump = false;
        case '--dry-run':
          dryRun = true;
        case '--skip-msix':
          skipMsix = true;
        case '--skip-setup':
          skipSetup = true;
        case '--skip-codegen':
          skipCodegen = true;
        case '--help' || '-h':
          stdout.writeln(
            'Usage: dart run tool/release.dart [platform ...] [options]\n'
            'Platforms: android ios macos windows all\n'
            'Options:\n'
            '  --no-bump       Build the current version without incrementing it.\n'
            '  --dry-run       Print the next version without changing or building.\n'
            '  --skip-msix     Windows: skip the .msix installer.\n'
            '  --skip-setup    Windows: skip the Inno Setup .exe installer.\n'
            '  --skip-codegen  Skip drift build_runner (if lib is already generated).\n'
            '\n'
            'Windows artifacts (when tools are available):\n'
            '  dist/kaijuan-x.y.z-windows.zip         portable\n'
            '  dist/kaijuan-x.y.z-windows.msix        MSIX installer\n'
            '  dist/kaijuan-x.y.z-windows-setup.exe   classic Setup.exe\n',
          );
          exit(0);
        case 'all':
          platforms
            ..clear()
            ..addAll(_defaultPlatformsForHost());
        default:
          if (!_knownPlatforms.contains(argument)) {
            throw FormatException('Unknown release argument: $argument');
          }
          if (!platforms.contains(argument)) platforms.add(argument);
      }
    }
    return _ReleaseOptions(
      bump: bump,
      dryRun: dryRun,
      platforms: platforms,
      skipMsix: skipMsix,
      skipSetup: skipSetup,
      skipCodegen: skipCodegen,
    );
  }

  final bool bump;
  final bool dryRun;
  final List<String> platforms;
  final bool skipMsix;
  final bool skipSetup;
  final bool skipCodegen;
}

class _ReleaseVersion {
  const _ReleaseVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.buildNumber,
  });

  factory _ReleaseVersion.read(String pubspec) {
    final match = RegExp(
      r'^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    if (match == null) {
      throw const FormatException('pubspec.yaml has no valid x.y.z version.');
    }
    return _ReleaseVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      buildNumber: int.tryParse(match.group(4) ?? '') ?? 0,
    );
  }

  final int major;
  final int minor;
  final int patch;
  final int buildNumber;

  String get name => '$major.$minor.$patch';

  /// MSIX requires a.b.c.d (four components).
  String get msixVersion => '$major.$minor.$patch.$buildNumber';

  _ReleaseVersion nextPatch() => _ReleaseVersion(
    major: major,
    minor: minor,
    patch: patch + 1,
    buildNumber: buildNumber + 1,
  );

  String applyTo(String pubspec) {
    return pubspec.replaceFirst(
      RegExp(r'^version:\s*[^\r\n]+', multiLine: true),
      'version: $name+$buildNumber',
    );
  }
}

List<String> _defaultPlatformsForHost() {
  if (Platform.isMacOS) return ['android', 'ios', 'macos'];
  if (Platform.isWindows) return ['android', 'windows'];
  return ['android'];
}

void _validatePlatforms(List<String> platforms) {
  if (platforms.isEmpty) {
    throw const FormatException('Select at least one release platform.');
  }
  if (platforms.contains('ios') && !Platform.isMacOS) {
    throw UnsupportedError('iOS releases require macOS.');
  }
  if (platforms.contains('macos') && !Platform.isMacOS) {
    throw UnsupportedError('macOS releases require macOS.');
  }
  if (platforms.contains('windows') && !Platform.isWindows) {
    throw UnsupportedError('Windows releases require Windows.');
  }
}

Future<void> _buildPlatform(
  String platform,
  _ReleaseVersion version,
  Directory dist,
  _ReleaseOptions options,
) async {
  stdout.writeln('\nBuilding $platform ${version.name}...');
  if (!options.skipCodegen) {
    await _run('dart', [
      'run',
      'build_runner',
      'build',
      '--delete-conflicting-outputs',
    ]);
  }
  switch (platform) {
    case 'android':
      await _flutterBuild('appbundle', version);
      await _flutterBuild('apk', version);
      await _copyArtifact(
        'build/app/outputs/bundle/release/app-release.aab',
        '${dist.path}/$_artifactPrefix-${version.name}-android.aab',
      );
      await _copyArtifact(
        'build/app/outputs/flutter-apk/app-release.apk',
        '${dist.path}/$_artifactPrefix-${version.name}-android.apk',
      );
    case 'ios':
      await _flutterBuild('ios', version, extra: ['--no-codesign']);
      final packageRoot = Directory(
        'build/release_package/ios-${version.name}',
      );
      if (packageRoot.existsSync()) await packageRoot.delete(recursive: true);
      await packageRoot.create(recursive: true);
      await _run('ditto', [
        'build/ios/iphoneos/Runner.app',
        '${packageRoot.path}/Payload/Runner.app',
      ]);
      await _run('ditto', [
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        'Payload',
        File(
          '${dist.path}/$_artifactPrefix-${version.name}-ios-unsigned.zip',
        ).absolute.path,
      ], workingDirectory: packageRoot.path);
    case 'macos':
      await _flutterBuild('macos', version);
      final macosApp = _resolveMacosAppBundle();
      await _run('ditto', [
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        macosApp,
        '${dist.path}/$_artifactPrefix-${version.name}-macos.zip',
      ]);
    case 'windows':
      await _buildWindows(version, dist, options);
  }
}

String _resolveMacosAppBundle() {
  for (final candidate in _macosAppCandidates) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  throw StateError(
    'Missing macOS Release app. Expected one of: '
    '${_macosAppCandidates.join(', ')}',
  );
}

Future<void> _buildWindows(
  _ReleaseVersion version,
  Directory dist,
  _ReleaseOptions options,
) async {
  await _flutterBuild('windows', version);

  final releaseDir = Directory('build/windows/x64/runner/Release');
  if (!releaseDir.existsSync()) {
    throw StateError('Missing Windows Release output: ${releaseDir.path}');
  }

  final zipPath = File(
    '${dist.path}/$_artifactPrefix-${version.name}-windows.zip',
  ).absolute.path;
  if (File(zipPath).existsSync()) await File(zipPath).delete();
  await _run('tar', [
    '-a',
    '-c',
    '-f',
    zipPath,
    '-C',
    releaseDir.path,
    '.',
  ]);
  stdout.writeln('Created $zipPath');

  if (!options.skipMsix) {
    await _buildWindowsMsix(version, dist);
  } else {
    stdout.writeln('Skipping MSIX (--skip-msix).');
  }

  if (!options.skipSetup) {
    await _buildWindowsSetup(version, dist);
  } else {
    stdout.writeln('Skipping Setup.exe (--skip-setup).');
  }
}

Future<void> _buildWindowsMsix(_ReleaseVersion version, Directory dist) async {
  stdout.writeln('Building MSIX ${version.msixVersion}...');
  final outputName = '$_artifactPrefix-${version.name}-windows';
  await _run('dart', [
    'run',
    'msix:create',
    '--build-windows',
    'false',
    '--version',
    version.msixVersion,
    '--output-path',
    dist.absolute.path,
    '--output-name',
    outputName,
    '--install-certificate',
    'false',
  ]);

  final produced = File('${dist.path}/$outputName.msix');
  if (!produced.existsSync()) {
    final fallback = await _findNewestMsix();
    if (fallback == null) {
      throw StateError('MSIX build finished but no .msix file was found.');
    }
    await fallback.copy(produced.path);
  }
  stdout.writeln('Created ${produced.path}');
}

Future<File?> _findNewestMsix() async {
  final roots = [
    Directory('dist'),
    Directory('build/windows'),
    Directory('.'),
  ];
  File? newest;
  DateTime? newestTime;
  for (final root in roots) {
    if (!root.existsSync()) continue;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.msix')) {
        continue;
      }
      final stat = await entity.stat();
      if (newestTime == null || stat.modified.isAfter(newestTime)) {
        newest = entity;
        newestTime = stat.modified;
      }
    }
  }
  return newest;
}

Future<void> _buildWindowsSetup(
  _ReleaseVersion version,
  Directory dist,
) async {
  final iscc = _findInnoSetupCompiler();
  if (iscc == null) {
    stderr.writeln('''
WARNING: Inno Setup 6 (ISCC.exe) not found — Setup.exe was not built.

Install Inno Setup 6, then re-run:
  winget install --id JRSoftware.InnoSetup -e --accept-package-agreements
  dart run tool/release.dart windows --no-bump --skip-msix

Script: $_windowsIss
See:    packaging/windows/README.md
''');
    return;
  }

  stdout.writeln('Building Setup.exe with $iscc ...');
  final script = File(_windowsIss).absolute.path;
  final outputBase = '$_artifactPrefix-${version.name}-windows-setup';
  final sourceDir = Directory(
    'build/windows/x64/runner/Release',
  ).absolute.path;
  final outputDir = dist.absolute.path;

  await _run(iscc, [
    script,
    '/DMyAppVersion=${version.name}',
    '/DMyAppPublisher=$_publisher',
    '/DSourceDir=$sourceDir',
    '/DOutputDir=$outputDir',
    '/DOutputBaseFilename=$outputBase',
    '/Q',
  ]);

  final setup = File('${dist.path}/$outputBase.exe');
  if (!setup.existsSync()) {
    throw StateError('Inno Setup finished but missing ${setup.path}');
  }
  stdout.writeln('Created ${setup.path}');
}

String? _findInnoSetupCompiler() {
  final which = _which('ISCC.exe') ?? _which('iscc.exe') ?? _which('iscc');
  if (which != null) return which;

  final candidates = <String>[
    r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    r'C:\Program Files\Inno Setup 6\ISCC.exe',
    if (Platform.environment['LOCALAPPDATA'] case final local?)
      '$local\\Programs\\Inno Setup 6\\ISCC.exe',
    if (Platform.environment['ProgramFiles(x86)'] case final pf86?)
      '$pf86\\Inno Setup 6\\ISCC.exe',
    if (Platform.environment['ProgramFiles'] case final pf?)
      '$pf\\Inno Setup 6\\ISCC.exe',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

String? _which(String command) {
  try {
    final result = Process.runSync(
      Platform.isWindows ? 'where.exe' : 'which',
      [command],
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) return null;
    final line = (result.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    return line.isEmpty ? null : line;
  } catch (_) {
    return null;
  }
}

Future<void> _flutterBuild(
  String target,
  _ReleaseVersion version, {
  List<String> extra = const [],
}) {
  return _run('flutter', [
    'build',
    target,
    '--release',
    '--build-name=${version.name}',
    '--build-number=${version.buildNumber}',
    ...extra,
  ]);
}

Future<void> _copyArtifact(String source, String destination) async {
  final file = File(source);
  if (!file.existsSync()) throw StateError('Missing release artifact: $source');
  await file.copy(destination);
  stdout.writeln('Created $destination');
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final resolved = _resolveExecutable(executable);
  stdout.writeln('> $resolved ${arguments.join(' ')}');
  final process = await Process.start(
    resolved,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(
      resolved,
      arguments,
      'Exited with code $code',
      code,
    );
  }
}

String _resolveExecutable(String executable) {
  if (!Platform.isWindows) return executable;
  if (executable.contains('\\') || executable.contains('/')) {
    return executable;
  }
  return switch (executable.toLowerCase()) {
    'flutter' => 'flutter.bat',
    'dart' => 'dart.bat',
    'powershell' => 'powershell.exe',
    _ => executable,
  };
}
