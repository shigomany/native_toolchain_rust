import 'dart:io';

import 'package:native_assets_cli/code_assets.dart';
import 'package:native_toolchain_rust/rustup.dart';
import 'package:native_toolchain_rust_common/native_toolchain_rust_common.dart';
import 'package:path/path.dart' as path;

const _cargoToml = '''
[workspace]

[package]
name = "linker_wrapper"
version = "0.1.0"
edition = "2021"

[dependencies]
''';

const _cargoLock = '''
# This file is automatically @generated by Cargo.
# It is not intended for manual editing.
version = 3

[[package]]
name = "linker_wrapper"
version = "0.1.0"
''';

const _mainRs = '''
fn main() {
    let args = std::env::args_os().skip(1);
    let clang = std::env::var("_CARGOKIT_NDK_LINK_CLANG")
        .expect("linker_wrapper: didn't find _CARGOKIT_NDK_LINK_CLANG env var");
    let target = std::env::var("_CARGOKIT_NDK_LINK_TARGET")
        .expect("linker_wrapper: didn't find _CARGOKIT_NDK_LINK_TARGET env var");

    let mut child = std::process::Command::new(&clang)
        .arg(target)
        .args(args)
        .spawn()
        .unwrap_or_else(|err| {
            eprintln!("linker_wrapper: Failed to spawn {clang:?} as linker: {err}");
            std::process::exit(1)
        });
    let status = child.wait().unwrap_or_else(|err| {
        eprintln!("cargokit (as linker): Failed to wait for {clang:?} to complete: {err}");
        std::process::exit(1);
    });

    std::process::exit(status.code().unwrap_or(1))
}
''';

/// This class is responsible for creating and building the linker wrapper.
/// This avoid using NDK wrapper scripts, which on windows cause problems when invoked
/// from rustc due to wrong CMD argument escaping.
///
/// https://github.com/android/ndk/issues/1856
class AndroidLinkerWrapper {
  final String tempDir;
  final RustupToolchain toolchain;

  AndroidLinkerWrapper({
    required this.tempDir,
    required this.toolchain,
  });

  Future<String> linkerWrapperPath() async {
    String wrapperRoot = path.join(tempDir, 'linker_wrapper_1.0');
    String executablePath = path.join(wrapperRoot, 'target', 'debug',
        OS.current.executableFileName('linker_wrapper'));
    if (!File(executablePath).existsSync()) {
      Directory(wrapperRoot).createSync(recursive: true);
      File(path.join(wrapperRoot, 'Cargo.toml')).writeAsStringSync(_cargoToml);
      File(path.join(wrapperRoot, 'Cargo.lock')).writeAsStringSync(_cargoLock);
      Directory(path.join(wrapperRoot, 'src')).createSync();
      File(path.join(wrapperRoot, 'src', 'main.rs')).writeAsStringSync(_mainRs);
      await runCommand(
        toolchain.rustup.executablePath,
        [
          'run',
          toolchain.name,
          'cargo',
          'build',
          '--quiet',
        ],
        workingDirectory: wrapperRoot,
      );
      if (!File(executablePath).existsSync()) {
        throw Exception('Failed to build linker wrapper');
      }
    }
    return executablePath;
  }
}
