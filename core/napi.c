// NAPI glue for libmimisubstore.so:  import core from 'libmimisubstore.so'
//   version(): string                 {"core"}
//   call(json): string                synchronous ops (status, logs, validate, parse, stop...)
//   callAsync(json): Promise<string>  same ops on a worker thread (start/stop/stopAll/parse)
#include <stdlib.h>
#include <string.h>
#include <napi/native_api.h>

extern char *MsVersion(void);
extern char *MsCall(char *js);
extern void MsFree(char *p);

static char *getStr(napi_env env, napi_value v) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, v, NULL, 0, &len) != napi_ok) {
        char *e = (char *)malloc(3);
        strcpy(e, "{}");
        return e;
    }
    char *buf = (char *)malloc(len + 1);
    napi_get_value_string_utf8(env, v, buf, len + 1, &len);
    buf[len] = 0;
    return buf;
}

static napi_value mkStr(napi_env env, char *s) {
    napi_value r;
    if (s != NULL) {
        napi_create_string_utf8(env, s, NAPI_AUTO_LENGTH, &r);
        MsFree(s);
    } else {
        napi_create_string_utf8(env, "", 0, &r);
    }
    return r;
}

typedef struct {
    char *a;
    char *out;
    napi_deferred deferred;
    napi_async_work work;
} Job;

static void execJob(napi_env env, void *data) {
    Job *j = (Job *)data;
    j->out = MsCall(j->a);
}

static void doneJob(napi_env env, napi_status status, void *data) {
    Job *j = (Job *)data;
    napi_resolve_deferred(env, j->deferred, mkStr(env, j->out));
    napi_delete_async_work(env, j->work);
    free(j->a);
    free(j);
}

static napi_value Version(napi_env env, napi_callback_info info) { return mkStr(env, MsVersion()); }

static napi_value Call(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);
    char *a = argc > 0 ? getStr(env, args[0]) : strdup("{}");
    char *out = MsCall(a);
    free(a);
    return mkStr(env, out);
}

static napi_value CallAsync(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);
    Job *j = (Job *)calloc(1, sizeof(Job));
    j->a = argc > 0 ? getStr(env, args[0]) : strdup("{}");
    napi_value promise, resName;
    napi_create_promise(env, &j->deferred, &promise);
    napi_create_string_utf8(env, "msCall", NAPI_AUTO_LENGTH, &resName);
    napi_create_async_work(env, NULL, resName, execJob, doneJob, j, &j->work);
    napi_queue_async_work(env, j->work);
    return promise;
}

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"version", NULL, Version, NULL, NULL, NULL, napi_default, NULL},
        {"call", NULL, Call, NULL, NULL, NULL, napi_default, NULL},
        {"callAsync", NULL, CallAsync, NULL, NULL, NULL, napi_default, NULL},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module msModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = NULL,
    .nm_register_func = Init,
    .nm_modname = "mimisubstore",
    .nm_priv = NULL,
    .reserved = {0},
};

__attribute__((constructor)) static void RegisterMimiSubStore(void) { napi_module_register(&msModule); }
