import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart' show FeatureFlags;
import '../../core/logging.dart';

// ─── Opaque Types ────────────────────────────────────────────

final class _OrtStatus extends Opaque {}
final class _OrtEnv extends Opaque {}
final class _OrtSession extends Opaque {}
final class _OrtMemoryInfo extends Opaque {}
final class _OrtValue extends Opaque {}

// ─── ort_bridge FFI Typedefs ─────────────────────────────────

typedef _InitC = Int32 Function(Pointer<Utf8>);
typedef _InitD = int Function(Pointer<Utf8>);
typedef _ShutdownC = Void Function();
typedef _ShutdownD = void Function();
typedef _CreateEnvC = Pointer<_OrtStatus> Function(Uint32, Pointer<Utf8>, Pointer<Pointer<_OrtEnv>>);
typedef _CreateEnvD = Pointer<_OrtStatus> Function(int, Pointer<Utf8>, Pointer<Pointer<_OrtEnv>>);
typedef _CreateCpuMemInfoC = Pointer<_OrtStatus> Function(Pointer<Pointer<_OrtMemoryInfo>>);
typedef _CreateCpuMemInfoD = Pointer<_OrtStatus> Function(Pointer<Pointer<_OrtMemoryInfo>>);
typedef _CreateSessionOptsC = Pointer<_OrtStatus> Function(Pointer<Pointer<Void>>);
typedef _CreateSessionOptsD = Pointer<_OrtStatus> Function(Pointer<Pointer<Void>>);
typedef _SetOptLevelC = Pointer<_OrtStatus> Function(Pointer<Void>, Uint32);
typedef _SetOptLevelD = Pointer<_OrtStatus> Function(Pointer<Void>, int);
typedef _CreateSessionC = Pointer<_OrtStatus> Function(Pointer<_OrtEnv>, Pointer<Void>, Int64, Pointer<Void>, Pointer<Pointer<_OrtSession>>);
typedef _CreateSessionD = Pointer<_OrtStatus> Function(Pointer<_OrtEnv>, Pointer<Void>, int, Pointer<Void>, Pointer<Pointer<_OrtSession>>);
typedef _CreateTensorC = Pointer<_OrtStatus> Function(Pointer<_OrtMemoryInfo>, Pointer<Float>, Int64, Pointer<Int64>, Int64, Pointer<Pointer<_OrtValue>>);
typedef _CreateTensorD = Pointer<_OrtStatus> Function(Pointer<_OrtMemoryInfo>, Pointer<Float>, int, Pointer<Int64>, int, Pointer<Pointer<_OrtValue>>);
typedef _RunC = Pointer<_OrtStatus> Function(Pointer<_OrtSession>, Pointer<Pointer<Utf8>>, Pointer<Pointer<_OrtValue>>, Int64, Pointer<Pointer<Utf8>>, Int64, Pointer<Pointer<_OrtValue>>);
typedef _RunD = Pointer<_OrtStatus> Function(Pointer<_OrtSession>, Pointer<Pointer<Utf8>>, Pointer<Pointer<_OrtValue>>, int, Pointer<Pointer<Utf8>>, int, Pointer<Pointer<_OrtValue>>);
typedef _GetTensorDataC = Pointer<_OrtStatus> Function(Pointer<_OrtValue>, Pointer<Pointer<Float>>, Pointer<Int64>);
typedef _GetTensorDataD = Pointer<_OrtStatus> Function(Pointer<_OrtValue>, Pointer<Pointer<Float>>, Pointer<Int64>);
typedef _GetCountC = Pointer<_OrtStatus> Function(Pointer<_OrtSession>, Pointer<Int64>);
typedef _GetCountD = Pointer<_OrtStatus> Function(Pointer<_OrtSession>, Pointer<Int64>);
typedef _GetNameC = Pointer<_OrtStatus> Function(Pointer<_OrtSession>, Int64, Pointer<Pointer<Utf8>>);
typedef _GetNameD = Pointer<_OrtStatus> Function(Pointer<_OrtSession>, int, Pointer<Pointer<Utf8>>);
typedef _GetErrMsgC = Pointer<Utf8> Function(Pointer<_OrtStatus>);
typedef _GetErrMsgD = Pointer<Utf8> Function(Pointer<_OrtStatus>);
typedef _ReleaseC = Void Function(Pointer<Void>);
typedef _ReleaseD = void Function(Pointer<Void>);

// ─── DirectML EP (GPU) ──────────────────────────────────────

typedef _EnableDmlC = Int32 Function(Pointer<Void>, Int32);
typedef _EnableDmlD = int Function(Pointer<Void>, int);

// ─── Constants ──────────────────────────────────────────────

const _kLogLevelWarning = 2;
const _kGraphOptEnableAll = 99;
const _kBridgeOk = 0;

/// DirectML (GPU) 是否可用 — 由 ort_bridge_enable_dml 返回值确定
const _kDmlAvailable = 0;

// ─── Enums & Result Model ───────────────────────────────────

enum MlModelStatus { notLoaded, loading, ready, error }

class MlInferenceResult {
  final List<Float32List> outputs;
  final List<List<int>> outputShapes;
  const MlInferenceResult({required this.outputs, required this.outputShapes});
}

class _ModelSession {
  final Pointer<_OrtSession> session;
  final Pointer<_OrtMemoryInfo> memInfo;
  final Pointer<_OrtEnv> env;
  final List<String> inputNames;
  final List<String> outputNames;
  _ModelSession({required this.session, required this.memInfo, required this.env, required this.inputNames, required this.outputNames});
}

// ─── MlService ──────────────────────────────────────────────

class MlService {
  bool _initialized = false;
  final Map<String, _ModelSession> _sessions = {};
  final Map<String, MlModelStatus> _status = {};
  Pointer<_OrtEnv>? _globalEnv; // ignore: unused_field

  _InitD? _init;
  _ShutdownD? _shutdown;
  _CreateEnvD? _createEnv;
  _CreateCpuMemInfoD? _createCpuMemInfo;
  _CreateSessionOptsD? _createSessionOpts;
  _SetOptLevelD? _setOptLevel;
  _CreateSessionD? _ffiCreateSession;
  _CreateTensorD? _createTensor;
  _RunD? _run;
  _GetTensorDataD? _getTensorData;
  _GetCountD? _getInputCount;
  _GetCountD? _getOutputCount;
  _GetNameD? _getInputName;
  _GetNameD? _getOutputName;
  _GetErrMsgD? _getErrMsg;
  _ReleaseD? _releaseEnv;
  _ReleaseD? _releaseSession;
  _ReleaseD? _releaseMemInfo;
  _ReleaseD? _releaseValue;
  _ReleaseD? _releaseStatus;
  _ReleaseD? _releaseSessionOpts;
  _EnableDmlD? _enableDml;

  /// DirectML (GPU) 是否已成功启用
  bool _dmlEnabled = false;

  /// 推理后端：'dml' (GPU) 或 'cpu'
  String get inferenceBackend => _dmlEnabled ? 'dml' : 'cpu';

  // ─── Public ─────────────────────────────────────────────

  bool get isAvailable { if (!FeatureFlags.aiMlEnabled) return false; _tryInit(); return _initialized; }
  MlModelStatus getStatus(String modelId) => _status[modelId] ?? MlModelStatus.notLoaded;

  Future<bool> loadModel(String assetPath, String modelId) async {
    if (!FeatureFlags.aiMlEnabled) { _status[modelId] = MlModelStatus.error; return false; }
    if (!isAvailable) { _status[modelId] = MlModelStatus.error; return false; }
    _status[modelId] = MlModelStatus.loading;
    try {
      final bytes = await rootBundle.load(assetPath);
      final tempDir = await getTemporaryDirectory();
      final modelFile = File(p.join(tempDir.path, '$modelId.onnx'));
      await modelFile.writeAsBytes(bytes.buffer.asUint8List());
      _createSession(modelId, bytes.buffer.asUint8List(), modelFile.path);
      return true;
    } catch (e) {
      _status[modelId] = MlModelStatus.error;
      AppLogger.error('ML', 'asset 加载失败', details: 'id: $modelId, error: $e');
      return false;
    }
  }

  Future<bool> loadModelFromFile(String filePath, String modelId) async {
    if (!FeatureFlags.aiMlEnabled) { _status[modelId] = MlModelStatus.error; return false; }
    if (!isAvailable) { _status[modelId] = MlModelStatus.error; return false; }
    _status[modelId] = MlModelStatus.loading;
    try {
      final file = File(filePath);
      if (!await file.exists()) throw Exception('Model file not found');
      final bytes = await file.readAsBytes();
      if (bytes.length < 4) throw Exception('Invalid ONNX file');
      AppLogger.debug('ML', '文件读取完成', details: 'size: ${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB');
      _createSession(modelId, bytes, filePath);
      return true;
    } catch (e) {
      _status[modelId] = MlModelStatus.error;
      AppLogger.error('ML', '文件加载失败', details: 'id: $modelId, error: $e');
      return false;
    }
  }

  Future<MlInferenceResult?> runInference(
    String modelId, List<Float32List> inputs, List<List<int>> inputShapes, {List<String>? outputNames}) async {
    final s = _sessions[modelId];
    if (s == null || _status[modelId] != MlModelStatus.ready) return null;
    try { return _runInference(s, inputs, inputShapes, outputNames); }
    catch (e) { AppLogger.error('ML', '推理异常', details: '$e'); return null; }
  }

  void unloadModel(String modelId) {
    final s = _sessions.remove(modelId);
    if (s != null) {
      _releaseSession!(s.session.cast<Void>());
      _releaseMemInfo!(s.memInfo.cast<Void>());
      _releaseEnv!(s.env.cast<Void>());
    }
    _status.remove(modelId);
  }

  void dispose() {
    for (final id in _sessions.keys.toList()) { unloadModel(id); }
    _status.clear();
    _shutdown?.call();
    _initialized = false;
  }

  // ─── Init ────────────────────────────────────────────────

  void _tryInit() {
    if (_initialized) return;
    try {
      final (lib, libPath) = _loadBridge();
      AppLogger.info('ML', 'ort_bridge.dll 已加载', details: '路径: $libPath');
      _loadFuncs(lib);

      final ortPath = _findOrt();
      AppLogger.info('ML', 'onnxruntime.dll 已定位', details: '路径: $ortPath');

      final ortNative = ortPath.toNativeUtf8();
      try {
        final rc = _init!(ortNative);
        if (rc != _kBridgeOk) throw Exception('ort_bridge_init 返回: $rc');
      } finally { malloc.free(ortNative); }

      // 创建全局 ORT env
      final envPtr = calloc<Pointer<_OrtEnv>>();
      final logId = 'spectra'.toNativeUtf8();
      try {
        final st = _createEnv!(_kLogLevelWarning, logId, envPtr);
        _checkStatus(st, 'CreateEnv');
        _globalEnv = envPtr.value;
      } finally {
        calloc.free(envPtr);
        malloc.free(logId);
      }

      _initialized = true;
      AppLogger.info('ML', 'ONNX Runtime 初始化成功');
    } catch (e) {
      _initialized = false;
      AppLogger.warn('ML', 'ONNX Runtime 不可用，将使用启发式引擎', details: '错误: $e');
    }
  }

  (DynamicLibrary, String) _loadBridge() {
    final candidates = <String>[
      p.join(Directory.current.path, 'ort_bridge.dll'),
      p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'ort_bridge.dll'),
      p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'ort_bridge.dll'),
    ];
    try {
      final ad = Platform.environment['APPDATA'];
      if (ad != null) {
        final sd = p.join(ad, 'com.example', 'spectra');
        candidates.addAll([p.join(sd, 'ort_bridge.dll'), p.join(sd, 'models', 'ort_bridge.dll')]);
      }
    } catch (_) {}
    for (final p in candidates) { try { return (DynamicLibrary.open(p), p); } catch (_) {} }
    try { return (DynamicLibrary.open('ort_bridge.dll'), 'ort_bridge.dll (PATH)'); }
    catch (e) { throw Exception('未找到 ort_bridge.dll: $e'); }
  }

  String _findOrt() {
    final candidates = <String>[
      p.join(Directory.current.path, 'onnxruntime.dll'),
      p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'onnxruntime.dll'),
      p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'onnxruntime.dll'),
    ];
    try {
      final ad = Platform.environment['APPDATA'];
      if (ad != null) {
        final sd = p.join(ad, 'com.example', 'spectra');
        candidates.addAll([p.join(sd, 'onnxruntime.dll'), p.join(sd, 'models', 'onnxruntime.dll')]);
      }
    } catch (_) {}
    for (final p in candidates) { if (File(p).existsSync()) return p; }
    return 'onnxruntime.dll';
  }

  void _loadFuncs(DynamicLibrary lib) {
    _init = lib.lookupFunction<_InitC, _InitD>('ort_bridge_init');
    _shutdown = lib.lookupFunction<_ShutdownC, _ShutdownD>('ort_bridge_shutdown');
    _createEnv = lib.lookupFunction<_CreateEnvC, _CreateEnvD>('ort_bridge_create_env');
    _createCpuMemInfo = lib.lookupFunction<_CreateCpuMemInfoC, _CreateCpuMemInfoD>('ort_bridge_create_cpu_memory_info');
    _createSessionOpts = lib.lookupFunction<_CreateSessionOptsC, _CreateSessionOptsD>('ort_bridge_create_session_options');
    _setOptLevel = lib.lookupFunction<_SetOptLevelC, _SetOptLevelD>('ort_bridge_set_session_graph_optimization_level');
    _ffiCreateSession = lib.lookupFunction<_CreateSessionC, _CreateSessionD>('ort_bridge_create_session_from_array');
    _createTensor = lib.lookupFunction<_CreateTensorC, _CreateTensorD>('ort_bridge_create_tensor_with_data');
    _run = lib.lookupFunction<_RunC, _RunD>('ort_bridge_run');
    _getTensorData = lib.lookupFunction<_GetTensorDataC, _GetTensorDataD>('ort_bridge_get_tensor_data_and_count');
    _getInputCount = lib.lookupFunction<_GetCountC, _GetCountD>('ort_bridge_session_get_input_count');
    _getOutputCount = lib.lookupFunction<_GetCountC, _GetCountD>('ort_bridge_session_get_output_count');
    _getInputName = lib.lookupFunction<_GetNameC, _GetNameD>('ort_bridge_session_get_input_name');
    _getOutputName = lib.lookupFunction<_GetNameC, _GetNameD>('ort_bridge_session_get_output_name');
    _getErrMsg = lib.lookupFunction<_GetErrMsgC, _GetErrMsgD>('ort_bridge_get_error_message');
    _releaseEnv = lib.lookupFunction<_ReleaseC, _ReleaseD>('ort_bridge_release_env');
    _releaseSession = lib.lookupFunction<_ReleaseC, _ReleaseD>('ort_bridge_release_session');
    _releaseMemInfo = lib.lookupFunction<_ReleaseC, _ReleaseD>('ort_bridge_release_memory_info');
    _releaseValue = lib.lookupFunction<_ReleaseC, _ReleaseD>('ort_bridge_release_value');
    _releaseStatus = lib.lookupFunction<_ReleaseC, _ReleaseD>('ort_bridge_release_status');
    _releaseSessionOpts = lib.lookupFunction<_ReleaseC, _ReleaseD>('ort_bridge_release_session_options');
    _enableDml = lib.lookupFunction<_EnableDmlC, _EnableDmlD>('ort_bridge_enable_dml');
  }

  // ─── Session ─────────────────────────────────────────────

  void _createSession(String modelId, Uint8List modelBytes, String debugPath) {
    unloadModel(modelId);
    final optsPtr = calloc<Pointer<Void>>();
    Pointer<Void>? opts;
    Pointer<_OrtSession>? session;
    Pointer<_OrtMemoryInfo>? memInfo;
    Pointer<_OrtEnv>? env;

    try {
      // 每个 session 创建独立 env（隔离）
      final envPtr = calloc<Pointer<_OrtEnv>>();
      final logId = modelId.toNativeUtf8();
      try {
        var st = _createEnv!(_kLogLevelWarning, logId, envPtr);
        _checkStatus(st, 'CreateEnv');
        env = envPtr.value;
      } finally {
        calloc.free(envPtr);
        malloc.free(logId);
      }

      var st = _createSessionOpts!(optsPtr);
      _checkStatus(st, 'CreateSessionOptions');
      opts = optsPtr.value;

      st = _setOptLevel!(opts, _kGraphOptEnableAll);
      _checkStatus(st, 'SetGraphOptimizationLevel');

      // 尝试启用 DirectML (GPU) 执行提供程序 — 失败时自动回退到 CPU
      if (_enableDml != null) {
        final dmlRc = _enableDml!(opts, 0);
        if (dmlRc == _kDmlAvailable) {
          _dmlEnabled = true;
          AppLogger.info('ML', 'DirectML (GPU) 已启用');
        } else {
          AppLogger.info('ML', 'DirectML 不可用，使用 CPU 推理');
        }
      }

      final modelData = calloc<Uint8>(modelBytes.length);
      try {
        for (var i = 0; i < modelBytes.length; i++) { modelData[i] = modelBytes[i]; }
        final sessionPtr = calloc<Pointer<_OrtSession>>();
        try {
          st = _ffiCreateSession!(env, modelData.cast<Void>(), modelBytes.length, opts, sessionPtr);
          _checkStatus(st, 'CreateSessionFromArray');
          session = sessionPtr.value;
        } finally { calloc.free(sessionPtr); }
      } finally { calloc.free(modelData); }

      final memInfoPtr = calloc<Pointer<_OrtMemoryInfo>>();
      try {
        st = _createCpuMemInfo!(memInfoPtr);
        _checkStatus(st, 'CreateCpuMemoryInfo');
        memInfo = memInfoPtr.value;
      } finally { calloc.free(memInfoPtr); }

      final inputNames = _queryNames(session, _getInputCount!, _getInputName!, fallback: ['input']);
      final outputNames = _queryNames(session, _getOutputCount!, _getOutputName!, fallback: ['output']);

      _sessions[modelId] = _ModelSession(session: session, memInfo: memInfo, env: env, inputNames: inputNames, outputNames: outputNames);
      _status[modelId] = MlModelStatus.ready;
      AppLogger.info('ML', '✅ 模型加载完成', details: 'id: $modelId, backend: $inferenceBackend, ins: $inputNames, outs: $outputNames');
    } catch (e) {
      if (memInfo != null) _releaseMemInfo!(memInfo.cast<Void>());
      if (session != null) _releaseSession!(session.cast<Void>());
      if (env != null) _releaseEnv!(env.cast<Void>());
      rethrow;
    } finally {
      if (opts != null) _releaseSessionOpts!(opts);
      calloc.free(optsPtr);
    }
  }

  List<String> _queryNames(Pointer<_OrtSession> session, _GetCountD fnCount, _GetNameD fnName, {List<String> fallback = const []}) {
    final countPtr = calloc<Int64>();
    final names = <String>[];
    try {
      var st = fnCount(session, countPtr);
      if (st != nullptr) { _logStatus(st); return fallback; }
      final count = countPtr.value;
      if (count <= 0) return fallback;
      for (var i = 0; i < count; i++) {
        final namePtr = calloc<Pointer<Utf8>>();
        st = fnName(session, i, namePtr);
        if (st != nullptr) { _logStatus(st); calloc.free(namePtr); continue; }
        if (namePtr.value != nullptr) names.add(namePtr.value.toDartString());
        calloc.free(namePtr);
      }
    } finally { calloc.free(countPtr); }
    return names.isNotEmpty ? names : fallback;
  }

  // ─── Inference ───────────────────────────────────────────

  MlInferenceResult? _runInference(_ModelSession s, List<Float32List> inputs, List<List<int>> inputShapes, List<String>? outputNames) {
    final effOuts = outputNames ?? s.outputNames;
    if (effOuts.isEmpty) return null;
    final nIn = inputs.length, nOut = effOuts.length;
    final inVals = <Pointer<_OrtValue>>[], inData = <Pointer<Float>>[];

    for (var i = 0; i < nIn; i++) {
      final data = inputs[i], shape = inputShapes[i];
      final dp = calloc<Float>(data.length);
      for (var j = 0; j < data.length; j++) { dp[j] = data[j]; }
      inData.add(dp);
      final sp = calloc<Int64>(shape.length);
      for (var j = 0; j < shape.length; j++) { sp[j] = shape[j]; }
      final vp = calloc<Pointer<_OrtValue>>();
      final st = _createTensor!(s.memInfo, dp, data.length, sp, shape.length, vp);
      calloc.free(sp);
      if (st != nullptr) { _cleanupInfer(inVals, inData, vp); _checkStatus(st); return null; }
      inVals.add(vp.value); calloc.free(vp);
    }

    final inNameNtv = <Pointer<Utf8>>[], inNamePtrs = calloc<Pointer<Utf8>>(nIn);
    for (var i = 0; i < nIn; i++) { final ns = (i < s.inputNames.length ? s.inputNames[i] : 'input').toNativeUtf8(); inNameNtv.add(ns); inNamePtrs[i] = ns; }
    final inValPtrs = calloc<Pointer<_OrtValue>>(nIn);
    for (var i = 0; i < nIn; i++) { inValPtrs[i] = inVals[i]; }
    final outNameNtv = <Pointer<Utf8>>[], outNamePtrs = calloc<Pointer<Utf8>>(nOut);
    for (var i = 0; i < nOut; i++) { final ns = effOuts[i].toNativeUtf8(); outNameNtv.add(ns); outNamePtrs[i] = ns; }
    final outValPtrs = calloc<Pointer<_OrtValue>>(nOut);

    try {
      final st = _run!(s.session, inNamePtrs, inValPtrs, nIn, outNamePtrs, nOut, outValPtrs);
      if (st != nullptr) { _checkStatus(st); return null; }

      final outputs = <Float32List>[], shapes = <List<int>>[];
      for (var i = 0; i < nOut; i++) {
        final v = outValPtrs[i];
        if (v == nullptr) continue;
        final dp = calloc<Pointer<Float>>(), cp = calloc<Int64>();
        final ss = _getTensorData!(v, dp, cp);
        if (ss != nullptr) { _logStatus(ss); calloc.free(dp); calloc.free(cp); continue; }
        final n = cp.value, fd = dp.value;
        if (n > 0 && fd != nullptr) {
          final out = Float32List(n);
          for (var j = 0; j < n; j++) { out[j] = fd[j]; }
          outputs.add(out); shapes.add([n]);
        } else { outputs.add(Float32List(0)); shapes.add([]); }
        calloc.free(dp); calloc.free(cp);
      }
      return MlInferenceResult(outputs: outputs, outputShapes: shapes);
    } finally {
      for (final v in inVals) { _releaseValue!(v.cast<Void>()); }
      for (var i = 0; i < nOut; i++) { if (outValPtrs[i] != nullptr) { _releaseValue!(outValPtrs[i].cast<Void>()); } }
      for (final p in inData) { calloc.free(p); }
      for (final ns in inNameNtv) { malloc.free(ns); }
      for (final ns in outNameNtv) { malloc.free(ns); }
      calloc.free(inNamePtrs); calloc.free(inValPtrs); calloc.free(outNamePtrs); calloc.free(outValPtrs);
    }
  }

  void _cleanupInfer(List<Pointer<_OrtValue>> vals, List<Pointer<Float>> data, Pointer<Pointer<_OrtValue>> vp) {
    for (final v in vals) { _releaseValue!(v.cast<Void>()); }
    for (final p in data) { calloc.free(p); }
    calloc.free(vp);
  }

  // ─── Helpers ─────────────────────────────────────────────

  void _checkStatus(Pointer<_OrtStatus>? st, [String op = '']) {
    if (st == null || st == nullptr) return;
    final m = _getErrMsg!(st);
    final e = m == nullptr ? 'unknown' : m.toDartString();
    _releaseStatus!(st.cast<Void>());
    throw Exception('ORT error${op.isNotEmpty ? ' [$op]' : ''}: $e');
  }

  void _logStatus(Pointer<_OrtStatus>? st) {
    if (st == null || st == nullptr) return;
    final m = _getErrMsg!(st);
    final e = m == nullptr ? 'unknown' : m.toDartString();
    _releaseStatus!(st.cast<Void>());
    AppLogger.error('ML', 'ORT error', details: e);
  }
}
