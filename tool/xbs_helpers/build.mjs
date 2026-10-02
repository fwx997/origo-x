import {build} from 'esbuild';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
const output = '../../assets/xbs/';
mkdirSync(output, {recursive: true});
await build({entryPoints:['index.js'],bundle:true,minify:true,format:'iife',platform:'browser',target:'es2020',outfile:output+'native_helpers.js'});
const names = ['@xmldom/xmldom','blueimp-md5','js-base64','parse5','xpath','entities'];
const licenses = names.map(name => {
  const base = `node_modules/${name}/`;
  const pkg = JSON.parse(readFileSync(base+'package.json','utf8'));
  let license;
  for (const filename of ['LICENSE','LICENSE.md','LICENSE.txt']) {
    try { license = readFileSync(base+filename,'utf8'); break; } catch {}
  }
  if (!license) throw new Error('Missing license for '+name);
  return `${name} ${pkg.version}\n${license}`;
});
writeFileSync(output+'THIRD_PARTY_LICENSES.txt',licenses.join('\n\n--------\n\n').replace(/[ \t]+$/gm, ''));
