/** libmimisubstore.so: Go core (embedded Sub-Store backend in goja + HTTP server + bundled web UI) + NAPI glue. */
/** {"core":"1.0.0","backend":"2.42.6","frontend":"2.34.1"} */
export const version: () => string;
/** Synchronous JSON op (see core/ssc/api.go). */
export const call: (json: string) => string;
/** Same ops on a worker thread (start loads the backend). */
export const callAsync: (json: string) => Promise<string>;
