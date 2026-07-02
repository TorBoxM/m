import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'common.dart';

// 打包为 ZIP（使用 archive 包）
Future<void> packZip({
  required String sourceDir,
  required String outputPath,
}) async {
  log('▶️  正在打包为 ZIP...');

  // 确保输出目录存在
  final outputDir = Directory(p.dirname(outputPath));
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  // 删除已存在的同名文件
  final outputFile = File(outputPath);
  if (await outputFile.exists()) {
    await outputFile.delete();
  }

  // 创建 Archive 对象
  final archive = Archive();

  // 递归添加所有文件
  final sourceDirectory = Directory(sourceDir);
  final files = sourceDirectory.listSync(recursive: true);

  for (final entity in files) {
    if (entity is File) {
      final relativePath = p.relative(entity.path, from: sourceDir);
      final bytes = await entity.readAsBytes();

      // 添加文件到归档
      final archiveFile = ArchiveFile(
        relativePath.replaceAll('\\', '/'), // 统一使用 / 作为路径分隔符
        bytes.length,
        bytes,
      );

      archive.addFile(archiveFile);

      // 显示进度
      log('📦 添加: $relativePath');
    }
  }

  log('📦 正在压缩（最大压缩率）...');

  // 使用 ZIP 编码器压缩，设置最大压缩等级（archive 4.x 使用 9）
  final encoder = ZipEncoder();
  final zipData = encoder.encode(archive, level: 9);

  // 写入 ZIP 文件
  await File(outputPath).writeAsBytes(zipData);

  // 显示文件大小
  final fileSize = await File(outputPath).length();
  final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
  log('✅ 打包完成: ${p.basename(outputPath)} ($sizeInMB MB)');
}

// ============================================================================
// Linux 打包函数
// ============================================================================

// Linux 打包入口：生成 deb + rpm + AppImage
Future<void> packLinuxInstallers({
  required String projectRoot,
  required String sourceDir,
  required String outputDir,
  required String appName,
  required String version,
  required String arch,
  required bool isDebug,
}) async {
  final debugSuffix = isDebug ? '-debug' : '';
  final appNameCapitalized =
      '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}';

  // 转换架构名称
  final debArch = _getDebArch(arch);
  final rpmArch = _getRpmArch(arch);

  // 打包 DEB
  await packDeb(
    projectRoot: projectRoot,
    sourceDir: sourceDir,
    outputPath: p.join(
      outputDir,
      '$appNameCapitalized-v$version-linux-$arch$debugSuffix.deb',
    ),
    appName: appName,
    version: version,
    arch: debArch,
  );

  // 打包 RPM
  await packRpm(
    projectRoot: projectRoot,
    sourceDir: sourceDir,
    outputPath: p.join(
      outputDir,
      '$appNameCapitalized-v$version-linux-$arch$debugSuffix.rpm',
    ),
    appName: appName,
    version: version,
    arch: rpmArch,
  );

  // 打包 AppImage
  await packAppImage(
    projectRoot: projectRoot,
    sourceDir: sourceDir,
    outputPath: p.join(
      outputDir,
      '$appNameCapitalized-v$version-linux-$arch$debugSuffix.AppImage',
    ),
    appName: appName,
    version: version,
  );
}

// 获取 DEB 架构名称

String _getDebArch(String arch) {
  switch (arch) {
    case 'x64':
      return 'amd64';
    case 'arm64':
      return 'arm64';
    default:
      return arch;
  }
}

// 获取 RPM 架构名称
String _getRpmArch(String arch) {
  switch (arch) {
    case 'x64':
      return 'x86_64';
    case 'arm64':
      return 'aarch64';
    default:
      return arch;
  }
}

// 打包为 DEB（Debian/Ubuntu）
Future<void> packDeb({
  required String projectRoot,
  required String sourceDir,
  required String outputPath,
  required String appName,
  required String version,
  required String arch,
}) async {
  log('▶️  正在打包为 DEB...');

  // 检查 dpkg-deb 是否可用
  final dpkgCheck = await Process.run('which', ['dpkg-deb']);
  if (dpkgCheck.exitCode != 0) {
    log('⚠️  dpkg-deb 未安装，跳过 DEB 打包');
    log('   提示：运行 dart run scripts/prebuild.dart --installer 安装打包工具');
    return;
  }

  final appNameCapitalized =
      '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}';
  final appNameLower = appName.toLowerCase();

  // 创建临时打包目录
  final tempDir = await Directory.systemTemp.createTemp('deb_build_');
  final debRoot = p.join(tempDir.path, '${appNameLower}_$version');

  try {
    // 创建 DEB 目录结构
    final installDir = p.join(debRoot, 'opt', appNameLower);
    final debianDir = p.join(debRoot, 'DEBIAN');
    final applicationsDir = p.join(debRoot, 'usr', 'share', 'applications');
    final iconsDir = p.join(
      debRoot,
      'usr',
      'share',
      'icons',
      'hicolor',
      '256x256',
      'apps',
    );

    await Directory(installDir).create(recursive: true);
    await Directory(debianDir).create(recursive: true);
    await Directory(applicationsDir).create(recursive: true);
    await Directory(iconsDir).create(recursive: true);

    // 复制应用文件
    await _copyDirectory(Directory(sourceDir), Directory(installDir));

    // 生成 control 文件
    final controlContent =
        '''
Package: $appNameLower
Version: $version
Section: net
Priority: optional
Architecture: $arch
Maintainer: $appNameCapitalized Team <support@$appNameLower.app>
Description: $appNameCapitalized - Network Proxy Client
 A modern network proxy client with a beautiful Flutter UI.
 Features system proxy, TUN mode, and traffic monitoring.
Depends: libgtk-3-0, libblkid1, liblzma5
''';
    await File(p.join(debianDir, 'control')).writeAsString(controlContent);

    // 生成 postinst 脚本（安装后执行）
    final postinstContent =
        '''
#!/bin/bash
set -e

# 设置可执行权限
chmod +x /opt/$appNameLower/$appNameLower
if [ -f /opt/$appNameLower/data/flutter_assets/assets/core/TorBoxCore ]; then
    chmod +x /opt/$appNameLower/data/flutter_assets/assets/core/TorBoxCore
fi

# 创建符号链接
ln -sf /opt/$appNameLower/$appNameLower /usr/local/bin/$appNameLower

# 更新桌面数据库
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database /usr/share/applications || true
fi
''';
    final postinstFile = File(p.join(debianDir, 'postinst'));
    await postinstFile.writeAsString(postinstContent);
    await Process.run('chmod', ['+x', postinstFile.path]);

    // 生成 prerm 脚本（卸载前执行）
    final prermContent =
        '''
#!/bin/bash
set -e

# 删除符号链接
rm -f /usr/local/bin/$appNameLower
''';
    final prermFile = File(p.join(debianDir, 'prerm'));
    await prermFile.writeAsString(prermContent);
    await Process.run('chmod', ['+x', prermFile.path]);

    // 生成 .desktop 文件
    final desktopContent =
        '''
[Desktop Entry]
Type=Application
Name=$appNameCapitalized
Comment=Network Proxy Client
Exec=/opt/$appNameLower/$appNameLower
Icon=$appNameLower
Terminal=false
Categories=Network;Utility;
StartupNotify=true
''';
    await File(
      p.join(applicationsDir, '$appNameLower.desktop'),
    ).writeAsString(desktopContent);

    // 复制图标（如果存在）
    final iconSource = File(
      p.join(
        projectRoot,
        'scripts',
        'pre_assets',
        'tray_icon',
        'linux',
        'proxy_enabled.png',
      ),
    );
    if (await iconSource.exists()) {
      await iconSource.copy(p.join(iconsDir, '$appNameLower.png'));
    }

    // 确保输出目录存在
    await Directory(p.dirname(outputPath)).create(recursive: true);

    // 构建 DEB 包
    final result = await Process.run('dpkg-deb', [
      '--build',
      '--root-owner-group',
      debRoot,
      outputPath,
    ]);

    if (result.exitCode != 0) {
      log('❌ DEB 打包失败');
      log(result.stderr);
      throw Exception('dpkg-deb 打包失败');
    }

    final fileSize = await File(outputPath).length();
    final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
    log('✅ DEB 打包完成: ${p.basename(outputPath)} ($sizeInMB MB)');
  } finally {
    // 清理临时目录
    await tempDir.delete(recursive: true);
  }
}

// 打包为 RPM（Fedora/RHEL/CentOS）
Future<void> packRpm({
  required String projectRoot,
  required String sourceDir,
  required String outputPath,
  required String appName,
  required String version,
  required String arch,
}) async {
  log('▶️  正在打包为 RPM...');

  // 检查 rpmbuild 是否可用
  final rpmCheck = await Process.run('which', ['rpmbuild']);
  if (rpmCheck.exitCode != 0) {
    log('⚠️  rpmbuild 未安装，跳过 RPM 打包');
    log('   提示：运行 dart run scripts/prebuild.dart --installer 安装打包工具');
    return;
  }

  final appNameCapitalized =
      '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}';
  final appNameLower = appName.toLowerCase();

  // 创建临时打包目录
  final tempDir = await Directory.systemTemp.createTemp('rpm_build_');
  final rpmBuildDir = tempDir.path;

  try {
    // 创建 RPM 构建目录结构
    final specDir = p.join(rpmBuildDir, 'SPECS');
    final sourcesDir = p.join(rpmBuildDir, 'SOURCES');
    final buildRootDir = p.join(rpmBuildDir, 'BUILDROOT');

    await Directory(specDir).create(recursive: true);
    await Directory(sourcesDir).create(recursive: true);
    await Directory(buildRootDir).create(recursive: true);

    // 创建 tarball
    final tarballName = '$appNameLower-$version.tar.gz';
    final tarballPath = p.join(sourcesDir, tarballName);

    // 创建临时目录用于 tarball
    final tarTempDir = await Directory.systemTemp.createTemp('rpm_tar_');
    final tarSourceDir = p.join(tarTempDir.path, '$appNameLower-$version');
    await Directory(tarSourceDir).create(recursive: true);
    await _copyDirectory(Directory(sourceDir), Directory(tarSourceDir));

    // 创建 tarball
    await Process.run('tar', [
      '-czf',
      tarballPath,
      '-C',
      tarTempDir.path,
      '$appNameLower-$version',
    ]);
    await tarTempDir.delete(recursive: true);

    // 生成 SPEC 文件
    final specContent =
        '''
Name:           $appNameLower
Version:        $version
Release:        1%{?dist}
Summary:        $appNameCapitalized - Network Proxy Client

License:        Proprietary
URL:            https://$appNameLower.app
Source0:        %{name}-%{version}.tar.gz

BuildArch:      $arch
Requires:       gtk3, libblkid, xz-libs

%description
A modern network proxy client with a beautiful Flutter UI.
Features system proxy, TUN mode, and traffic monitoring.

%prep
%setup -q

%install
mkdir -p %{buildroot}/opt/%{name}
cp -r * %{buildroot}/opt/%{name}/

mkdir -p %{buildroot}/usr/share/applications
cat > %{buildroot}/usr/share/applications/%{name}.desktop << EOF
[Desktop Entry]
Type=Application
Name=$appNameCapitalized
Comment=Network Proxy Client
Exec=/opt/%{name}/%{name}
Icon=%{name}
Terminal=false
Categories=Network;Utility;
StartupNotify=true
EOF

mkdir -p %{buildroot}/usr/local/bin
ln -sf /opt/%{name}/%{name} %{buildroot}/usr/local/bin/%{name}

%files
/opt/%{name}
/usr/share/applications/%{name}.desktop
/usr/local/bin/%{name}

%post
chmod +x /opt/%{name}/%{name}
if [ -f /opt/%{name}/data/flutter_assets/assets/core/TorBoxCore ]; then
    chmod +x /opt/%{name}/data/flutter_assets/assets/core/TorBoxCore
fi
update-desktop-database /usr/share/applications || true

%preun
# 卸载前无需特殊操作

%changelog
* \$(date '+%a %b %d %Y') $appNameCapitalized Team <support@$appNameLower.app> - $version-1
- Initial package
''';
    await File(
      p.join(specDir, '$appNameLower.spec'),
    ).writeAsString(specContent);

    // 构建 RPM 包
    final result = await Process.run('rpmbuild', [
      '-bb',
      '--define',
      '_topdir $rpmBuildDir',
      p.join(specDir, '$appNameLower.spec'),
    ]);

    if (result.exitCode != 0) {
      log('❌ RPM 打包失败');
      log(result.stderr);
      throw Exception('rpmbuild 打包失败');
    }

    // 查找生成的 RPM 文件
    final rpmsDir = Directory(p.join(rpmBuildDir, 'RPMS', arch));
    if (await rpmsDir.exists()) {
      final rpmFiles = await rpmsDir
          .list()
          .where((f) => f.path.endsWith('.rpm'))
          .toList();
      if (rpmFiles.isNotEmpty) {
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await File(rpmFiles.first.path).copy(outputPath);

        final fileSize = await File(outputPath).length();
        final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
        log('✅ RPM 打包完成: ${p.basename(outputPath)} ($sizeInMB MB)');
      }
    } else {
      log('⚠️  未找到生成的 RPM 文件');
    }
  } finally {
    // 清理临时目录
    await tempDir.delete(recursive: true);
  }
}

// 打包为 AppImage（通用 Linux 格式）
Future<void> packAppImage({
  required String projectRoot,
  required String sourceDir,
  required String outputPath,
  required String appName,
  required String version,
}) async {
  log('▶️  正在打包为 AppImage...');

  // appimagetool 存放在 assets/tools 目录
  final appImageToolPath = p.join(
    projectRoot,
    'assets',
    'tools',
    'appimagetool',
  );
  if (!await File(appImageToolPath).exists()) {
    log('⚠️  appimagetool 未安装，跳过 AppImage 打包');
    log('   提示：运行 dart run scripts/prebuild.dart --installer 安装打包工具');
    return;
  }

  final appNameCapitalized =
      '${appName.substring(0, 1).toUpperCase()}${appName.substring(1)}';
  final appNameLower = appName.toLowerCase();

  // 创建临时 AppDir 目录
  final tempDir = await Directory.systemTemp.createTemp('appimage_build_');
  final appDir = p.join(tempDir.path, '$appNameCapitalized.AppDir');

  try {
    // 创建 AppDir 结构
    final usrBinDir = p.join(appDir, 'usr', 'bin');
    final usrLibDir = p.join(appDir, 'usr', 'lib');
    final usrShareDir = p.join(appDir, 'usr', 'share');
    final applicationsDir = p.join(usrShareDir, 'applications');
    final iconsDir = p.join(usrShareDir, 'icons', 'hicolor', '256x256', 'apps');

    await Directory(usrBinDir).create(recursive: true);
    await Directory(usrLibDir).create(recursive: true);
    await Directory(applicationsDir).create(recursive: true);
    await Directory(iconsDir).create(recursive: true);

    // 复制应用文件到 usr/bin
    await _copyDirectory(Directory(sourceDir), Directory(usrBinDir));

    // 生成 AppRun 脚本
    final appRunContent =
        '''
#!/bin/bash
SELF=\$(readlink -f "\$0")
HERE=\${SELF%/*}
export PATH="\$HERE/usr/bin:\$PATH"
export LD_LIBRARY_PATH="\$HERE/usr/lib:\$HERE/usr/bin/lib:\$LD_LIBRARY_PATH"
exec "\$HERE/usr/bin/$appNameLower" "\$@"
''';
    final appRunFile = File(p.join(appDir, 'AppRun'));
    await appRunFile.writeAsString(appRunContent);
    await Process.run('chmod', ['+x', appRunFile.path]);

    // 生成 .desktop 文件
    final desktopContent =
        '''
[Desktop Entry]
Type=Application
Name=$appNameCapitalized
Comment=Network Proxy Client
Exec=$appNameLower
Icon=$appNameLower
Terminal=false
Categories=Network;Utility;
StartupNotify=true
''';
    await File(
      p.join(appDir, '$appNameLower.desktop'),
    ).writeAsString(desktopContent);
    await File(
      p.join(applicationsDir, '$appNameLower.desktop'),
    ).writeAsString(desktopContent);

    // 复制图标
    final iconSource = File(
      p.join(
        projectRoot,
        'scripts',
        'pre_assets',
        'tray_icon',
        'linux',
        'proxy_enabled.png',
      ),
    );
    if (await iconSource.exists()) {
      await iconSource.copy(p.join(appDir, '$appNameLower.png'));
      await iconSource.copy(p.join(iconsDir, '$appNameLower.png'));
    } else {
      // 创建一个空的占位图标
      log('⚠️  未找到图标文件，将使用默认图标');
    }

    // 确保输出目录存在
    await Directory(p.dirname(outputPath)).create(recursive: true);

    // 构建 AppImage
    final result = await Process.run(
      appImageToolPath,
      [appDir, outputPath],
      environment: {'ARCH': 'x86_64'},
    );

    if (result.exitCode != 0) {
      log('❌ AppImage 打包失败');
      log(result.stderr);
      throw Exception('appimagetool 打包失败');
    }

    final fileSize = await File(outputPath).length();
    final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
    log('✅ AppImage 打包完成: ${p.basename(outputPath)} ($sizeInMB MB)');
  } finally {
    // 清理临时目录
    await tempDir.delete(recursive: true);
  }
}

// 辅助函数：递归复制目录

// 递归复制目录
Future<void> _copyDirectory(Directory source, Directory destination) async {
  if (!await destination.exists()) {
    await destination.create(recursive: true);
  }

  await for (final entity in source.list(recursive: false)) {
    final newPath = p.join(destination.path, p.basename(entity.path));

    if (entity is File) {
      await entity.copy(newPath);
    } else if (entity is Directory) {
      await _copyDirectory(entity, Directory(newPath));
    }
  }
}
