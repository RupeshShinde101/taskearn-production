// Netlify pre-deploy build script
// Stamps a unique version into sw.js cache name and all HTML asset query strings
// so browsers/SWs always fetch the latest files after each deploy.
const fs = require('fs');

const ts = Date.now();
const v = 'v' + ts; // e.g. v1778146235200

// 1. Stamp SW cache name (triggers SW re-install on all clients)
const swf = fs.readFileSync('sw.js', 'utf8');
fs.writeFileSync('sw.js', swf.replace(/workmate4u-v[a-zA-Z0-9]+/, 'workmate4u-' + v));

// 2. Stamp ?v= query strings in all HTML files (busts browser + SW cache for JS/CSS)
//    Pattern matches ?v=<anything> and replaces with ?v=<timestamp>
//    Works on every subsequent deploy because digits are in [0-9].
const htmlFiles = fs.readdirSync('.').filter(function(f) { return f.endsWith('.html'); });
htmlFiles.forEach(function(file) {
    let c = fs.readFileSync(file, 'utf8');
    c = c.replace(/\?v=[a-zA-Z0-9_]+/g, '?v=' + ts);
    fs.writeFileSync(file, c);
});

console.log('[netlify-build] Stamped version:', v, '| HTML files updated:', htmlFiles.length);
