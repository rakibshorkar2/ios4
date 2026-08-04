import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class GithubUpdater {
  static const String _githubApiUrl =
      'https://api.github.com/repos/rakibshorkar2/dirxplore1/releases/latest';

  static Future<UpdateInfo?> checkUpdate({String? customRepoUrl}) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
      ));

      final repoUrl = customRepoUrl ?? _githubApiUrl;

      // Make request directly to github
      final response = await dio.get(repoUrl);

      if (response.statusCode == 200) {
        final data = response.data;
        final latestRef = data['tag_name'] as String?;
        final releaseNotes = data['body'] as String?;
        final assets = data['assets'] as List?;

        String? downloadUrl;
        if (assets != null && assets.isNotEmpty) {
          try {
            // Priority: Assets ending with .apk
            final apkAsset =
                assets.firstWhere((a) => a['name'].toString().endsWith('.apk'));
            downloadUrl = apkAsset['browser_download_url'];
          } catch (_) {
            // Fallback: Just take the first asset
            downloadUrl = assets[0]['browser_download_url'];
          }
        }

        if (latestRef != null && downloadUrl != null) {
          final packageInfo = await PackageInfo.fromPlatform();
          final currentVersion = packageInfo.version;

          // Normalize versions (remove 'v' and build numbers like +4)
          final lVersion = latestRef.split('+')[0].replaceAll('v', '').trim();
          final cVersion =
              currentVersion.split('+')[0].replaceAll('v', '').trim();

          if (_isNewerVersion(cVersion, lVersion)) {
            return UpdateInfo(
              version: latestRef,
              downloadUrl: downloadUrl,
              releaseNotes: releaseNotes,
            );
          }
        }
      }
    } catch (e) {
      // SILENT
    }
    return null;
  }

  static bool _isNewerVersion(String current, String latest) {
    try {
      final cp = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final lp = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final c = i < cp.length ? cp[i] : 0;
        final l = i < lp.length ? lp[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }

      // If x.y.z are equal, check if latest has more components or if we want to support build numbers
      if (lp.length > cp.length) {
        for (int i = cp.length; i < lp.length; i++) {
          if (lp[i] > 0) return true;
        }
      }
    } catch (_) {}
    return false;
  }
}

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String? releaseNotes;

  UpdateInfo(
      {required this.version, required this.downloadUrl, this.releaseNotes});
}
