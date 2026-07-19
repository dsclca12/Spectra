/**
 * ort_bridge.c — ONNX Runtime bridge implementation
 *
 * Dynamically loads onnxruntime.dll and routes all calls through the OrtApi vtable.
 * This works around the fact that ONNX Runtime v1.27+ only exports OrtGetApiBase()
 * as a direct DLL symbol; all other functions live in the OrtApi vtable.
 */

#include "ort_bridge.h"

/* Include the full ONNX Runtime header to get struct definitions */
#define ORT_DLL_IMPORT
#include "onnxruntime_c_api.h"

#include <windows.h>

/* ─── Internal State ───────────────────────────────────────── */

static HMODULE       g_ort_dll    = NULL;
static const OrtApi* g_api        = NULL;

/* ─── Helpers ──────────────────────────────────────────────── */

static void* get_exports_table(void) {
    /* OrtGetApiBase is the only directly exported symbol.
       Get it from the loaded DLL. */
    if (!g_ort_dll) return NULL;
    return (void*)GetProcAddress(g_ort_dll, "OrtGetApiBase");
}

/* ─── Public API ───────────────────────────────────────────── */

ORT_BRIDGE_API int ort_bridge_init(const char* ortDllPath) {
    if (g_api) return ORT_BRIDGE_OK; /* already initialized */

    /* Load onnxruntime.dll */
    const char* path = ortDllPath ? ortDllPath : "onnxruntime.dll";
    g_ort_dll = LoadLibraryA(path);
    if (!g_ort_dll) return ORT_BRIDGE_DLL_MISS;

    /* Get OrtGetApiBase */
    typedef const OrtApiBase* (ORT_API_CALL * OrtGetApiBaseFunc)(void);
    OrtGetApiBaseFunc getApiBase = (OrtGetApiBaseFunc)GetProcAddress(g_ort_dll, "OrtGetApiBase");
    if (!getApiBase) {
        FreeLibrary(g_ort_dll);
        g_ort_dll = NULL;
        return ORT_BRIDGE_INIT_FAIL;
    }

    /* Get OrtApiBase and then OrtApi */
    const OrtApiBase* base = getApiBase();
    if (!base) {
        FreeLibrary(g_ort_dll);
        g_ort_dll = NULL;
        return ORT_BRIDGE_INIT_FAIL;
    }

    g_api = base->GetApi(ORT_API_VERSION);
    if (!g_api) {
        FreeLibrary(g_ort_dll);
        g_ort_dll = NULL;
        return ORT_BRIDGE_INIT_FAIL;
    }

    return ORT_BRIDGE_OK;
}

ORT_BRIDGE_API void ort_bridge_shutdown(void) {
    g_api = NULL;
    if (g_ort_dll) {
        FreeLibrary(g_ort_dll);
        g_ort_dll = NULL;
    }
}

/* ─── Environment ──────────────────────────────────────────── */

ORT_BRIDGE_API OrtStatus* ort_bridge_create_env(
    uint32_t logLevel, const char* logId, OrtEnv** envOut) {
    if (!g_api) return NULL;
    return g_api->CreateEnv((OrtLoggingLevel)logLevel, logId, envOut);
}

/* ─── Memory Info ──────────────────────────────────────────── */

ORT_BRIDGE_API OrtStatus* ort_bridge_create_cpu_memory_info(
    OrtMemoryInfo** out) {
    if (!g_api) return NULL;
    return g_api->CreateCpuMemoryInfo(OrtMemTypeDefault, OrtDeviceAllocator, out);
}

/* ─── Session Options ──────────────────────────────────────── */

ORT_BRIDGE_API OrtStatus* ort_bridge_create_session_options(
    void** optsOut) {
    if (!g_api) return NULL;
    return g_api->CreateSessionOptions((OrtSessionOptions**)optsOut);
}

ORT_BRIDGE_API OrtStatus* ort_bridge_set_session_graph_optimization_level(
    void* opts, uint32_t level) {
    if (!g_api) return NULL;
    return g_api->SetSessionGraphOptimizationLevel((OrtSessionOptions*)opts, (GraphOptimizationLevel)level);
}

/* ─── DirectML Execution Provider ──────────────────────────── */

ORT_BRIDGE_API int ort_bridge_enable_dml(void* opts, int deviceId) {
    if (!g_api) return ORT_BRIDGE_ERROR;
    if (!g_ort_dll) return ORT_BRIDGE_ERROR;

    /* OrtSessionOptionsAppendExecutionProvider_DML is exported directly
       from onnxruntime.dll (not through the OrtApi vtable).
       Try to load it dynamically – gracefully degrade to CPU if unavailable. */
    typedef OrtStatus* (ORT_API_CALL * AppendExecutionProviderDmlFunc)(
        OrtSessionOptions*, int);
    
    AppendExecutionProviderDmlFunc appendDml = 
        (AppendExecutionProviderDmlFunc)GetProcAddress(
            g_ort_dll, "OrtSessionOptionsAppendExecutionProvider_DML");
    
    if (!appendDml) {
        /* DirectML not available in this ONNX Runtime build – fall back to CPU */
        return ORT_BRIDGE_ERROR;
    }

    OrtStatus* status = appendDml((OrtSessionOptions*)opts, deviceId);
    if (status) {
        /* DML init failed (e.g., no GPU, no DirectML support) – fall back to CPU */
        g_api->ReleaseStatus(status);
        return ORT_BRIDGE_ERROR;
    }

    return ORT_BRIDGE_OK;
}

/* ─── Session ──────────────────────────────────────────────── */

ORT_BRIDGE_API OrtStatus* ort_bridge_create_session_from_array(
    OrtEnv* env, const void* modelData, int64_t modelSize,
    void* opts, OrtSession** sessionOut) {
    if (!g_api) return NULL;
    return g_api->CreateSessionFromArray(env, modelData, (size_t)modelSize,
                                         (const OrtSessionOptions*)opts, sessionOut);
}

/* ─── Tensor ───────────────────────────────────────────────── */

ORT_BRIDGE_API OrtStatus* ort_bridge_create_tensor_with_data(
    OrtMemoryInfo* info, const float* data, int64_t dataLen,
    const int64_t* shape, int64_t rank, OrtValue** valueOut) {
    if (!g_api) return NULL;
    return g_api->CreateTensorWithDataAsOrtValue(
        info, (void*)data, (size_t)(dataLen * sizeof(float)),
        shape, (size_t)rank, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, valueOut);
}

/* ─── Inference ────────────────────────────────────────────── */

ORT_BRIDGE_API OrtStatus* ort_bridge_run(
    OrtSession* session,
    const char* const* inputNames, const OrtValue* const* inputs, int64_t nInputs,
    const char* const* outputNames, int64_t nOutputs,
    OrtValue** outputs) {
    if (!g_api) return NULL;
    return g_api->Run(session, NULL, inputNames, inputs, (size_t)nInputs,
                      outputNames, (size_t)nOutputs, outputs);
}

/* ─── Tensor Query ─────────────────────────────────────────── */

ORT_BRIDGE_API OrtStatus* ort_bridge_get_tensor_data_and_count(
    OrtValue* value, float** dataOut, int64_t* countOut) {
    if (!g_api) return NULL;

    /* Get tensor type and shape */
    OrtTensorTypeAndShapeInfo* info = NULL;
    OrtStatus* s = g_api->GetTensorTypeAndShape(value, &info);
    if (s) return s;

    /* Get element count from shape */
    size_t count = 0;
    s = g_api->GetTensorShapeElementCount(info, &count);
    if (s) {
        g_api->ReleaseTensorTypeAndShapeInfo(info);
        return s;
    }
    *countOut = (int64_t)count;
    g_api->ReleaseTensorTypeAndShapeInfo(info);

    /* Get mutable data pointer */
    return g_api->GetTensorMutableData(value, (void**)dataOut);
}


/* ─── Session Query ────────────────────────────────────────── */

ORT_BRIDGE_API OrtStatus* ort_bridge_session_get_input_count(
    OrtSession* session, int64_t* countOut) {
    if (!g_api) return NULL;
    size_t count = 0;
    OrtStatus* s = g_api->SessionGetInputCount(session, &count);
    if (!s) *countOut = (int64_t)count;
    return s;
}

ORT_BRIDGE_API OrtStatus* ort_bridge_session_get_output_count(
    OrtSession* session, int64_t* countOut) {
    if (!g_api) return NULL;
    size_t count = 0;
    OrtStatus* s = g_api->SessionGetOutputCount(session, &count);
    if (!s) *countOut = (int64_t)count;
    return s;
}

ORT_BRIDGE_API OrtStatus* ort_bridge_session_get_input_name(
    OrtSession* session, int64_t index, char** nameOut) {
    if (!g_api) return NULL;
    OrtAllocator* alloc = NULL;
    OrtStatus* s = g_api->GetAllocatorWithDefaultOptions(&alloc);
    if (s) return s;
    s = g_api->SessionGetInputName(session, (size_t)index, alloc, nameOut);
    return s;
}

ORT_BRIDGE_API OrtStatus* ort_bridge_session_get_output_name(
    OrtSession* session, int64_t index, char** nameOut) {
    if (!g_api) return NULL;
    OrtAllocator* alloc = NULL;
    OrtStatus* s = g_api->GetAllocatorWithDefaultOptions(&alloc);
    if (s) return s;
    s = g_api->SessionGetOutputName(session, (size_t)index, alloc, nameOut);
    return s;
}

/* ─── Error ────────────────────────────────────────────────── */

ORT_BRIDGE_API const char* ort_bridge_get_error_message(OrtStatus* status) {
    if (!g_api || !status) return "unknown error";
    return g_api->GetErrorMessage(status);
}

/* ─── Release ──────────────────────────────────────────────── */

ORT_BRIDGE_API void ort_bridge_release_env(OrtEnv* env) {
    if (g_api && env) g_api->ReleaseEnv(env);
}

ORT_BRIDGE_API void ort_bridge_release_session(OrtSession* session) {
    if (g_api && session) g_api->ReleaseSession(session);
}

ORT_BRIDGE_API void ort_bridge_release_memory_info(OrtMemoryInfo* info) {
    if (g_api && info) g_api->ReleaseMemoryInfo(info);
}

ORT_BRIDGE_API void ort_bridge_release_value(OrtValue* value) {
    if (g_api && value) g_api->ReleaseValue(value);
}

ORT_BRIDGE_API void ort_bridge_release_status(OrtStatus* status) {
    if (g_api && status) g_api->ReleaseStatus(status);
}

ORT_BRIDGE_API void ort_bridge_release_session_options(void* opts) {
    if (g_api && opts) g_api->ReleaseSessionOptions((OrtSessionOptions*)opts);
}

/* ─── Version ──────────────────────────────────────────────── */

ORT_BRIDGE_API const char* ort_bridge_version(void) {
    return "ort_bridge 1.0";
}

