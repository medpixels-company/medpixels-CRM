import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config.dart';

class AppUpdateInfo {
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String releaseNotes;
  final bool isMandatory;

  AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.releaseNotes,
    required this.isMandatory,
  });
}

class UpdateService {
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final response = await Supabase.instance.client
          .from('app_versions')
          .select()
          .eq('platform', 'android')
          .order('version_code', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final latestCode = response['version_code'] as int;
      if (latestCode > AppConfig.appVersionCode) {
        return AppUpdateInfo(
          versionName: response['version_name'] ?? '',
          versionCode: latestCode,
          apkUrl: response['apk_url'] ?? '',
          releaseNotes: response['release_notes'] ?? 'تحسينات جديدة في الأداء والاستقرار',
          isMandatory: response['is_mandatory'] ?? false,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Error checking for update: $e');
      return null;
    }
  }

  static Future<void> downloadAndInstallApk({
    required String apkUrl,
    required void Function(double progress) onProgress,
  }) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await client.send(request);

      final totalBytes = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/update.apk');

      if (await file.exists()) {
        await file.delete();
      }

      int receivedBytes = 0;
      final sink = file.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      }).asFuture();

      await sink.close();

      // تشغيل مثبت الحزم لتثبيت الـ APK مباشرة فوق التطبيق
      final result = await OpenFilex.open(file.path);
      debugPrint('Install APK status: ${result.type}');
    } catch (e) {
      debugPrint('Failed to download/install APK: $e');
      rethrow;
    }
  }
}

