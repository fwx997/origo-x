import 'dart:async';
import 'dart:convert';

import 'package:fjs/fjs.dart';
import 'package:flutter/services.dart';

import '../protocol/book_source_protocol.dart';
import '../services/source_task_pool.dart';

abstract interface class XbsJavascript {
  Future<Object?> evaluate(
    String code,
    Map<String, dynamic> config,
    Map<String, dynamic> params,
    Object? result,
  );
  Future<void> close();
}

class XbsQuickJs implements XbsJavascript {
  XbsQuickJs({Map<String, Object?>? cache}) : _cache = cache ?? {};

  static Future<void>? _initialization;
  static Future<String>? _helpers;
  final Map<String, Object?> _cache;
  JsEngine? _engine;

  Future<JsEngine> _getEngine() async {
    await (_initialization ??= LibFjs.init());
    if (_engine case final engine?) return engine;
    final engine = await JsEngine.create(
      builtins: const JsBuiltinOptions(
        abort: false,
        assert_: false,
        asyncHooks: false,
        buffer: false,
        childProcess: false,
        console: false,
        crypto: false,
        dgram: false,
        dns: false,
        events: false,
        exceptions: false,
        fetch: false,
        fs: false,
        https: false,
        intl: false,
        navigator: false,
        net: false,
        os: false,
        path: false,
        perfHooks: false,
        process: false,
        streamWeb: false,
        stringDecoder: false,
        temporal: false,
        timers: false,
        tty: false,
        url: false,
        util: false,
        zlib: false,
        json: false,
      ),
      runtimeOptions: JsEngineRuntimeOptions(
        memoryLimit: BigInt.from(32 * 1024 * 1024),
        maxStackSize: BigInt.from(512 * 1024),
      ),
    );
    await engine.initWithoutBridge();
    try {
      final helpers = await (_helpers ??= rootBundle.loadString(
        'assets/xbs/native_helpers.js',
      ));
      await engine
          .eval(source: JsCode.code(helpers))
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      await engine.close();
      rethrow;
    }
    _engine = engine;
    return engine;
  }

  @override
  Future<Object?> evaluate(
    String code,
    Map<String, dynamic> config,
    Map<String, dynamic> params,
    Object? result,
  ) => SourceTaskPool.scripts.run(
    '${identityHashCode(this)}',
    () => _evaluate(code, config, params, result),
    cancellation: SourceTaskContext.cancellation,
  );

  Future<Object?> _evaluate(
    String code,
    Map<String, dynamic> config,
    Map<String, dynamic> params,
    Object? result,
  ) async {
    final cancellation = SourceTaskContext.cancellation;
    cancellation?.throwIfCancelled();
    if (code.length > 512 * 1024) {
      throw const BookSourceProtocolException('香色脚本过大');
    }
    final engine = await _getEngine();
    void cancelScript() => unawaited(close());
    cancellation?.addListener(cancelScript);
    // Data is encoded as JSON, never interpolated into quoted JavaScript strings.
    final arguments = [
      config,
      params,
      result,
      _cache,
    ].map(jsonEncode).join(',');
    final wrapped =
        '(function(config,params,result,cache){'
        'const changes=[];'
        'params.nativeTool=globalThis.__xbsCreateNativeTool(cache,changes);'
        'const value=(function(){ $code\n })();'
        'return JSON.stringify({value:value===undefined?null:value,changes});'
        '})($arguments)';
    try {
      final value = await engine
          .eval(
            source: JsCode.code(wrapped),
            options: JsEvalOptions(global: true, strict: false, promise: false),
          )
          .timeout(const Duration(seconds: 2));
      cancellation?.throwIfCancelled();
      final envelope = jsonDecode(value.value as String) as Map;
      for (final change in envelope['changes'] as List) {
        _cache.remove(change[0]);
        _cache[change[0] as String] = change[1];
      }
      while (_cache.length > 128 || jsonEncode(_cache).length > 256 * 1024) {
        _cache.remove(_cache.keys.first);
      }
      return envelope['value'];
    } on TimeoutException {
      await close(); // FJS close interrupts the native runtime, including loops.
      throw const BookSourceProtocolException('香色脚本执行超时');
    } catch (_) {
      cancellation?.throwIfCancelled();
      throw const BookSourceProtocolException('香色脚本执行失败，可能依赖未适配的功能');
    } finally {
      cancellation?.removeListener(cancelScript);
    }
  }

  @override
  Future<void> close() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) await engine.close();
  }
}
