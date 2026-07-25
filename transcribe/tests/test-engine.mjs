/* Prüft die Live-Erkennung mit einem nachgebauten SpeechRecognition:
   Mix-Auswahl, Auto-Neustart, Zwischenergebnisse, Offline-Shell, Backup. */
import { chromium } from 'playwright';
let fails = 0;
const ok = (n,c,x='') => { console.log((c?'  ✓ ':'  ✗ ')+n+(c?'':' — '+x)); if(!c) fails++; };

const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined });
const ctx = await browser.newContext({ permissions:['microphone'], viewport:{width:412,height:900} });
await ctx.addInitScript(() => {
  const ac = new AudioContext();
  navigator.mediaDevices.getUserMedia = async () => {
    const o=ac.createOscillator(), g=ac.createGain(), d=ac.createMediaStreamDestination();
    o.frequency.value=210; g.gain.value=.35; o.connect(g); g.connect(d); o.start(); return d.stream;
  };
  /* Nachbau der Browser-Spracherkennung */
  class FakeSR {
    constructor(){ this.lang='de-DE'; this.continuous=false; this.interimResults=false; FakeSR.all.push(this); }
    start(){ this.running=true; FakeSR.starts.push(this.lang); this.onstart&&this.onstart(); }
    stop(){ this.running=false; this.onend&&this.onend(); }
    abort(){ this.running=false; this.onend&&this.onend(); }
    emit(text, conf, isFinal=true){
      const res=[Object.assign([{transcript:text,confidence:conf}],{isFinal,length:1})];
      this.onresult&&this.onresult({resultIndex:0, results:Object.assign(res,{length:1})});
    }
  }
  FakeSR.all=[]; FakeSR.starts=[];
  window.SpeechRecognition = window.webkitSpeechRecognition = FakeSR;
  window.__FakeSR = FakeSR;
});
const page = await ctx.newPage();
page.on('pageerror', e => { console.log('PAGEERROR', e.message); fails++; });
page.on('dialog', d => d.accept());
await page.goto('http://localhost:8765/transcribe/', { waitUntil:'networkidle' });

console.log('\n== Erkenner starten ==');
await page.click('.lang[data-lang="mix"]');
await page.click('#btnMic');
await page.waitForTimeout(600);
const starts = await page.evaluate(()=>window.__FakeSR.starts.slice());
ok('Mix startet zwei Erkenner (de + en)', starts.includes('de-DE') && starts.includes('en-US'), JSON.stringify(starts));

console.log('\n== Zwischenergebnis ==');
await page.evaluate(()=>{ const e=window.__FakeSR.all.find(r=>r.lang==='de-DE'); e.emit('ich schreibe gerade', .8, false); });
await page.waitForTimeout(200);
ok('Interim wird angezeigt', (await page.locator('#interim').textContent()).includes('ich schreibe'));

console.log('\n== Mix-Auswahl: deutscher Satz ==');
await page.evaluate(()=>{
  const de=window.__FakeSR.all.find(r=>r.lang==='de-DE'), en=window.__FakeSR.all.find(r=>r.lang==='en-US');
  de.emit('ich habe das heute nicht mehr geschafft', .88);
  en.emit('is harbor those hooter niched mere gershaft', .85);
});
await page.waitForTimeout(400);
let segs = await page.evaluate(()=>VN.session.segments.map(s=>({t:s.text,l:s.lang})));
ok('deutsches Ergebnis gewinnt', segs.length===1 && segs[0].l==='de', JSON.stringify(segs));

console.log('\n== Mix-Auswahl: englischer Satz ==');
await page.evaluate(()=>{
  const de=window.__FakeSR.all.find(r=>r.lang==='de-DE'), en=window.__FakeSR.all.find(r=>r.lang==='en-US');
  de.emit('lets tag e look ätt se pull request', .84);
  en.emit('lets take a look at the pull request', .86);
});
await page.waitForTimeout(400);
segs = await page.evaluate(()=>VN.session.segments.map(s=>({t:s.text,l:s.lang})));
ok('englisches Ergebnis gewinnt', segs.length===2 && segs[1].l==='en', JSON.stringify(segs));

console.log('\n== Einzelnes Ergebnis ohne Gegenstück ==');
await page.evaluate(()=>{ window.__FakeSR.all.find(r=>r.lang==='de-DE').emit('nur eine seite spricht', .9); });
await page.waitForTimeout(1200);
ok('wird nach kurzer Wartezeit übernommen', (await page.evaluate(()=>VN.session.segments.length))===3);

console.log('\n== Diktier-Befehl im Live-Fluss ==');
await page.evaluate(()=>{ window.__FakeSR.all.find(r=>r.lang==='de-DE').emit('das war ein test Komma und noch mehr Punkt', .9); });
await page.waitForTimeout(1200);
const lastSeg = await page.evaluate(()=>VN.session.segments.at(-1).text);
ok('Satzzeichen eingesetzt', lastSeg==='Das war ein test, und noch mehr.', JSON.stringify(lastSeg));

console.log('\n== Automatischer Neustart nach onend ==');
const before = await page.evaluate(()=>window.__FakeSR.starts.length);
await page.evaluate(()=>{ window.__FakeSR.all.forEach(r=>{ if(r.running) r.onend&&r.onend(); }); });
await page.waitForTimeout(1600);
const after = await page.evaluate(()=>window.__FakeSR.starts.length);
ok('Erkenner startet von selbst neu', after>before, before+' → '+after);

console.log('\n== Pause & Sprecherwechsel ==');
await page.click('#btnPause');
await page.waitForTimeout(300);
ok('Pause stoppt Erkenner', await page.evaluate(()=>VN.session&&document.querySelector('#btnPause').textContent==='▶︎'));
await page.click('#btnPause');
await page.waitForTimeout(300);
await page.click('#btnSpeaker');
await page.evaluate(()=>{ window.__FakeSR.all.find(r=>r.lang==='de-DE').emit('jetzt spricht die zweite person', .9); });
await page.waitForTimeout(1200);
ok('Sprecher B markiert', await page.evaluate(()=>VN.session.segments.at(-1).speaker==='B'));
ok('Sprecher B farblich getrennt', (await page.locator('.seg.spkB').count())>=1);

await page.click('#btnMic');
await page.waitForTimeout(1500);
ok('Erkenner nach Stopp beendet', await page.evaluate(()=>window.__FakeSR.all.every(r=>!r.running)));

console.log('\n== Backup & Import ==');
await page.click('#btnArchive');
await page.waitForTimeout(400);
const dl = page.waitForEvent('download');
await page.click('#btnBackup');
const f = await dl;
const path = await f.path();
const json = JSON.parse(await (await import('node:fs/promises')).readFile(path,'utf8'));
ok('Backup enthält Sitzungen', json.sessions.length>=1, JSON.stringify(Object.keys(json)));
ok('Key wird nicht mitgesichert', json.settings.apiKey==='', JSON.stringify(json.settings.apiKey));
await page.setInputFiles('#importFile', path);
await page.waitForTimeout(600);
ok('Import ohne Duplikate', (await page.locator('#archList .item').count())===json.sessions.length);
await page.click('#sheetArchive [data-close]');

console.log('\n== Offline (Service Worker) ==');
await page.waitForTimeout(800);
await ctx.setOffline(true);
await page.reload({ waitUntil:'domcontentloaded' }).catch(e=>{ console.log('reload:', e.message); fails++; });
ok('App lädt offline', (await page.title()).includes('Voice Notes'));
ok('Archiv offline verfügbar', await page.evaluate(async()=>(await VN.DB.all('sessions')).length>0));
await ctx.setOffline(false);

await browser.close();
console.log('\n'+(fails? '❌ '+fails+' Prüfungen fehlgeschlagen' : '✅ Alle Engine-Prüfungen bestanden'));
process.exit(fails?1:0);
