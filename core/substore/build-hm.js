const { build } = require('esbuild');
const { builtinModules } = require('module');
const names = new Set(builtinModules.map((n) => n.replace(/^node:/, '')));
build({
  entryPoints: ['src/products/sub-store-hm.js'],
  bundle: true, minify: !process.env.SS_NOMIN, platform: 'browser', format: 'iife',
  target: process.env.SS_TARGET || 'es2020',
  outfile: 'dist/sub-store-hm.js',
  inject: [require.resolve('core-js/actual/object/has-own')],
  plugins: [{ name: 'ext', setup(b) { b.onResolve({ filter: /.*/ }, (a) => {
    if (a.path !== 'buffer' && names.has(a.path.replace(/^node:/, ''))) return { path: a.path, external: true };
  }); } }],
}).then(() => {
  const fs = require('fs');
  let c = fs.readFileSync('dist/sub-store-hm.js', 'utf8');
  // direct eval makes every enclosing scope dynamic; indirect eval is enough (only globals are read)
  c = c.replace(/(^|[^A-Za-z0-9_$.])eval\(/g, '$1(0,eval)(');
  fs.writeFileSync('dist/sub-store-hm.js', c);
  console.log('ok');
}).catch((e) => { console.error(e.message); process.exit(1); });
