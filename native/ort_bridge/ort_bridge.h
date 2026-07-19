/**
 * ort_bridge.h — Minimal ONNX Runtime bridge for dart:ffi
 *
 * Exposes a flat C API for ONNX Runtime inference.
 * Internally uses OrtGetApiBase() → OrtApi vtable to resolve all functions.
 */

#ifndef ORT_BRIDGE_H
#define ORT_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
#ifdef ORT_BRIDGE_EXPORTS
#define ORT_BRIDGE_API __declspec(dllexport)
#else
#define ORT_BRIDGE_API __declspec(dllimport)
#endif
#else
#define ORT_BRIDGE_API
#endif

/* ─── Opaque handles (match ONNX Runtime internal types) ─── */
typedef struct OrtStatus    OrtStatus;
typedef struct OrtEnv       OrtEnv;
typedef struct OrtSession   OrtSession;
typedef struct OrtMemoryInfo OrtMemoryInfo;
typedef struct OrtValue     OrtValue;

/* ─── Constants ──────────────────────────────────────────── */
#define ORT_BRIDGE_OK        0
#define ORT_BRIDGE_ERROR    -1
#define ORT_BRIDGE_DLL_MISS  -2
#define ORT_BRIDGE_INIT_FAIL -3

/* ─── API ───────────────────────────────────────────────── */

/**
 * Initialize the bridge.
 *
 * [ortDllPath]  Path to onnxruntime.dll (NULL to search system/default paths).
 * Returns ORT_BRIDGE_OK on success, negative on failure.
 */
ORT_BRIDGE_API int ort_bridge_init(const char* ortDllPath);

/**
 * Shutdown the bridge. Frees all internal state.
 */
ORT_BRIDGE_API void ort_bridge_shutdown(void);

/**
 * Create ONNX Runtime environment.
 *
 * [logLevel]    Logging level (2=warning, 3=error).
 * [logId]       Identifier for logging.
 * [envOut]      Receives the OrtEnv handle.
 * Returns NULL on success (NULL = no error in ONNX Runtime convention),
 * or a non-NULL OrtStatus* on failure.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_create_env(
    uint32_t logLevel, const char* logId, OrtEnv** envOut);

/**
 * Create CPU memory info.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_create_cpu_memory_info(
    OrtMemoryInfo** out);

/**
 * Create session options.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_create_session_options(
    void** optsOut);

/**
 * Set session graph optimization level.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_set_session_graph_optimization_level(
    void* opts, uint32_t level);

/**
 * Try to enable the DirectML execution provider (GPU acceleration).
 *
 * [opts]     Session options pointer (from ort_bridge_create_session_options).
 * [deviceId] DirectML device ID (0 = default GPU).
 *
 * Returns ORT_BRIDGE_OK on success, ORT_BRIDGE_ERROR if DML is not available.
 * Gracefully degrades to CPU if DML is not supported on this system.
 */
ORT_BRIDGE_API int ort_bridge_enable_dml(void* opts, int deviceId);

/**
 * Create session from in-memory model bytes.
 *
 * [env]         OrtEnv.
 * [modelData]   Model bytes buffer.
 * [modelSize]   Size in bytes.
 * [opts]        Session options (or NULL).
 * [sessionOut]  Receives the OrtSession handle.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_create_session_from_array(
    OrtEnv* env, const void* modelData, int64_t modelSize,
    void* opts, OrtSession** sessionOut);

/**
 * Create a tensor from existing data (zero-copy).
 *
 * [info]        Memory info (from ort_bridge_create_cpu_memory_info).
 * [data]        Float32 data pointer (must remain valid during inference).
 * [dataLen]     Number of float elements.
 * [shape]       Array of dimension sizes.
 * [rank]        Number of dimensions.
 * [valueOut]    Receives the OrtValue handle.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_create_tensor_with_data(
    OrtMemoryInfo* info, const float* data, int64_t dataLen,
    const int64_t* shape, int64_t rank, OrtValue** valueOut);

/**
 * Run inference.
 *
 * [session]         OrtSession.
 * [inputNames]      Array of input name strings.
 * [inputs]          Array of OrtValue handles.
 * [nInputs]         Number of inputs.
 * [outputNames]     Array of output name strings.
 * [nOutputs]        Number of outputs.
 * [outputs]         Output buffer — will be filled with OrtValue handles.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_run(
    OrtSession* session,
    const char* const* inputNames, const OrtValue* const* inputs, int64_t nInputs,
    const char* const* outputNames, int64_t nOutputs,
    OrtValue** outputs);

/**
 * Get tensor data and element count.
 *
 * [value]      OrtValue handle.
 * [dataOut]    Receives pointer to the float data (ORT-owned, do not free).
 * [countOut]   Receives total number of float elements.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_get_tensor_data_and_count(
    OrtValue* value, float** dataOut, int64_t* countOut);

/**
 * Get number of model inputs.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_session_get_input_count(
    OrtSession* session, int64_t* countOut);

/**
 * Get number of model outputs.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_session_get_output_count(
    OrtSession* session, int64_t* countOut);

/**
 * Get input/output name at index.
 * The returned string is owned by ORT; caller must NOT free it.
 */
ORT_BRIDGE_API OrtStatus* ort_bridge_session_get_input_name(
    OrtSession* session, int64_t index, char** nameOut);

ORT_BRIDGE_API OrtStatus* ort_bridge_session_get_output_name(
    OrtSession* session, int64_t index, char** nameOut);

/**
 * Get error message from an OrtStatus.
 * The returned string is owned by ORT; caller must NOT free it.
 */
ORT_BRIDGE_API const char* ort_bridge_get_error_message(OrtStatus* status);

/**
 * Release resources.
 */
ORT_BRIDGE_API void ort_bridge_release_env(OrtEnv* env);
ORT_BRIDGE_API void ort_bridge_release_session(OrtSession* session);
ORT_BRIDGE_API void ort_bridge_release_memory_info(OrtMemoryInfo* info);
ORT_BRIDGE_API void ort_bridge_release_value(OrtValue* value);
ORT_BRIDGE_API void ort_bridge_release_status(OrtStatus* status);
ORT_BRIDGE_API void ort_bridge_release_session_options(void* opts);

/**
 * Get bridge version string.
 */
ORT_BRIDGE_API const char* ort_bridge_version(void);

#ifdef __cplusplus
}
#endif

#endif /* ORT_BRIDGE_H */
