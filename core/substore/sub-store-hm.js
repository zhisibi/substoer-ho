/**
 * SubStore HO: HarmonyOS embedded entry. Runs in an embedded JS engine with a
 * GUI.for.Cores-style host ($Plugins). serve() registers every route and the
 * patched express adapter exposes globalThis.__ssDispatch(req) instead of
 * dispatching a single $request.
 */
import migrate from '@/utils/migration';
import serve from '@/restful';

migrate();
serve();
