import 'dart:async';
import 'dart:io';

import 'package:TorBox/clash/client/clash_core_client.dart';
import 'package:TorBox/clash/config/clash_defaults.dart';
import 'package:TorBox/clash/services/delay_test_service.dart';
import 'package:TorBox/services/log_print_service.dart';

// Clash 代理管理器
// 负责代理节点的切换、延迟测试
class ProxyManager {
  final ClashCoreClient _coreClient;
  final bool Function() _isCoreRunning;
  final String Function() _getTestUrl;
  final Map<int, Completer<void>> _androidDelayTestCancelSignals = {};

  ProxyManager({
    required ClashCoreClient coreClient,
    required bool Function() isCoreRunning,
    required String Function() getTestUrl,
  }) : _coreClient = coreClient,
       _isCoreRunning = isCoreRunning,
       _getTestUrl = getTestUrl;

  int generateDelayTestRequestId() {
    return DelayTestService.generateRequestId();
  }

  Completer<void> _registerAndroidDelayTestCancelSignal(int requestId) {
    return _androidDelayTestCancelSignals.putIfAbsent(
      requestId,
      () => Completer<void>(),
    );
  }

  void _removeAndroidDelayTestCancelSignal(
    int requestId,
    Completer<void> cancelSignal,
  ) {
    final activeSignal = _androidDelayTestCancelSignals[requestId];
    if (identical(activeSignal, cancelSignal)) {
      _androidDelayTestCancelSignals.remove(requestId);
    }
  }

  Future<int> _awaitAndroidDelayTestWithCancel(
    int requestId,
    Future<int> delayFuture,
    Completer<void> cancelSignal,
  ) async {
    return await Future.any([
      delayFuture,
      cancelSignal.future.then((_) {
        Logger.info('Android 延迟测试已取消：requestId=$requestId');
        return -1;
      }),
    ]);
  }

  void cancelDelayTests(int requestId) {
    if (Platform.isAndroid) {
      final cancelSignal = _androidDelayTestCancelSignals[requestId];
      if (cancelSignal != null && !cancelSignal.isCompleted) {
        cancelSignal.complete();
        Logger.info('已取消 Android 延迟测试：requestId=$requestId');
      }
      return;
    }

    DelayTestService.cancelDelayTests(requestId);
  }

  // 获取代理列表
  Future<Map<String, dynamic>> getProxies() async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    return await _coreClient.getProxies();
  }

  // 切换代理节点
  Future<bool> changeProxy(String groupName, String proxyName) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    final wasSuccessful = await _coreClient.changeProxy(groupName, proxyName);

    // 切换节点后关闭所有现有连接，确保立即生效
    if (wasSuccessful) {
      await _coreClient.closeAllConnections();
    }

    return wasSuccessful;
  }

  // 测试代理延迟（使用 ClashCoreClient）
  Future<int> testProxyDelay(String proxyName, {String? testUrl}) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    return await _coreClient.testProxyDelay(
      proxyName,
      testUrl: testUrl ?? _getTestUrl(),
    );
  }

  // 测试单个代理节点延迟
  // Android 平台使用 JNI，桌面平台使用 Rust IPC
  Future<int> testProxyDelayViaRust(
    String proxyName, {
    required int requestId,
    String? testUrl,
  }) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    if (Platform.isAndroid) {
      final cancelSignal = _registerAndroidDelayTestCancelSignal(requestId);
      try {
        return await _awaitAndroidDelayTestWithCancel(
          requestId,
          _coreClient.testProxyDelay(
            proxyName,
            testUrl: testUrl ?? _getTestUrl(),
          ),
          cancelSignal,
        );
      } finally {
        _removeAndroidDelayTestCancelSignal(requestId, cancelSignal);
      }
    }

    return await DelayTestService.testProxyDelay(
      proxyName,
      requestId: requestId,
      testUrl: testUrl ?? _getTestUrl(),
    );
  }

  // 批量测试代理节点延迟
  // Android 平台使用 JNI 并发测试，桌面平台使用 Rust IPC
  Future<Map<String, int>> testGroupDelays(
    List<String> proxyNames, {
    required int requestId,
    String? testUrl,
    Function(String nodeName)? onNodeStart,
    Function(String nodeName, int delay)? onNodeComplete,
  }) async {
    if (!_isCoreRunning()) {
      throw Exception('Clash 未在运行');
    }

    if (Platform.isAndroid) {
      return await _testGroupDelaysViaJni(
        proxyNames,
        requestId: requestId,
        testUrl: testUrl,
        onNodeStart: onNodeStart,
        onNodeComplete: onNodeComplete,
      );
    }

    return await DelayTestService.testGroupDelays(
      proxyNames,
      requestId: requestId,
      testUrl: testUrl ?? _getTestUrl(),
      onNodeStart: onNodeStart,
      onNodeComplete: onNodeComplete,
    );
  }

  // Android 平台：通过 JNI 并发测试延迟
  Future<Map<String, int>> _testGroupDelaysViaJni(
    List<String> proxyNames, {
    required int requestId,
    String? testUrl,
    Function(String nodeName)? onNodeStart,
    Function(String nodeName, int delay)? onNodeComplete,
  }) async {
    final results = <String, int>{};
    final url = testUrl ?? _getTestUrl();
    final concurrency = ClashDefaults.delayTestConcurrency;
    final cancelSignal = _registerAndroidDelayTestCancelSignal(requestId);

    Logger.info(
      '开始批量延迟测试（JNI）：requestId=$requestId, ${proxyNames.length} 个节点，并发数=$concurrency',
    );

    try {
      // 分批并发测试
      for (var i = 0; i < proxyNames.length; i += concurrency) {
        if (cancelSignal.isCompleted) {
          Logger.info('Android 批量延迟测试已取消：requestId=$requestId');
          return results;
        }

        final batch = proxyNames.skip(i).take(concurrency).toList();
        final batchIndex = i ~/ concurrency + 1;
        final totalBatches =
            (proxyNames.length + concurrency - 1) ~/ concurrency;
        Logger.debug('测试批次 $batchIndex/$totalBatches：${batch.join(', ')}');

        final futures = batch.map((nodeName) async {
          if (cancelSignal.isCompleted) {
            return;
          }

          onNodeStart?.call(nodeName);
          final delay = await _awaitAndroidDelayTestWithCancel(
            requestId,
            _coreClient.testProxyDelay(nodeName, testUrl: url),
            cancelSignal,
          );

          if (cancelSignal.isCompleted) {
            Logger.debug(
              'Android 节点延迟测试已取消：requestId=$requestId, node=$nodeName',
            );
            return;
          }

          results[nodeName] = delay;
          Logger.debug('节点 $nodeName 延迟：${delay == -1 ? "超时" : "${delay}ms"}');
          onNodeComplete?.call(nodeName, delay);
        });
        await Future.wait(futures);
      }

      final successCount = results.values.where((d) => d > 0).length;
      Logger.info(
        '批量延迟测试完成：requestId=$requestId, 成功=$successCount，超时=${results.length - successCount}',
      );

      return results;
    } finally {
      _removeAndroidDelayTestCancelSignal(requestId, cancelSignal);
    }
  }
}
