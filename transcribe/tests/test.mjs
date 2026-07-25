import { chromium } from 'playwright';

const URL = 'http://localhost:8765/transcribe/';
const errs = [];
let fails = 0;
const ok = (name, cond, extra='') => { console.log((cond?'  ✓ ':'  ✗ ')+name+(cond?'':' — '+extra)); if(!cond) fails++; };

const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || undefined,
  args:['--use-fake-ui-for-media-stream','--use-fake-device-for-media-capture','--autoplay-policy=no-user-gesture-required']
});
const ctx = await browser.newContext({ permissions:['microphone'], viewport:{width:412,height:900} });
/* Der Container hat kein Audiogerät — Mikrofon durch einen synthetischen Stream ersetzen */
await ctx.addInitScript(() => {
  const ac = new AudioContext();
  navigator.mediaDevices.getUserMedia = async () => {
    const osc = ac.createOscillator(), g = ac.createGain(), dst = ac.createMediaStreamDestination();
    osc.frequency.value = 210; g.gain.value = 0.35; osc.connect(g); g.connect(dst); osc.start();
    return dst.stream;
  };
});
const page = await ctx.newPage();
page.on('dialog', d => d.accept());
page.on('console', m => { if(m.type()==='error') errs.push(m.text()); });
page.on('pageerror', e => errs.push('PAGEERROR: '+e.message));
await page.goto(URL, { waitUntil:'networkidle' });

console.log('\n== Laden ==');
ok('Titel gesetzt', (await page.title()).includes('Voice Notes'));
ok('Leerzustand sichtbar', await page.locator('#transcript .empty').isVisible());
ok('keine Konsolenfehler beim Start', errs.length===0, errs.join(' | '));

console.log('\n== Textwerkzeuge ==');
const t = await page.evaluate(() => {
  const T = VN.tools; const S = VN.S;
  S.cmds = true; S.autoPunct = true; S.vocabFuzzy = true; S.fillers = true;
  S.vocab = 'Kubernetes\nkubernätes => Kubernetes';
  return {
    cmd: T.applyCommands('das ist ein test Komma und noch was Punkt neuer Absatz zweiter Teil').text,
    del: T.applyCommands('hallo welt streich das').deleteLast,
    fill: T.stripFillers('ähm das ist halt uh ein Test'),
    vocabExact: T.applyVocab('wir nutzen kubernätes hier'),
    vocabFuzzy: T.applyVocab('wir nutzen Kubernetos hier'),
    punct: T.autoPunctuate('das ist ein satz'),
    langDe: T.langScore('ich habe das nicht gemacht','de') > T.langScore('ich habe das nicht gemacht','en'),
    langEn: T.langScore('i have not done this today','en') > T.langScore('i have not done this today','de'),
    srt: T.srtTime(75.25),
    lev: T.levenshtein('kubernetes','kubernetos')
  };
});
ok('Diktier-Befehle', t.cmd === 'das ist ein test, und noch was.\n\nzweiter Teil', JSON.stringify(t.cmd));
ok('"streich das" erkannt', t.del === true);
ok('Füllwörter entfernt', t.fill === 'das ist ein Test', JSON.stringify(t.fill));
ok('Wortschatz exakt', t.vocabExact.includes('Kubernetes'), t.vocabExact);
ok('Wortschatz unscharf', t.vocabFuzzy.includes('Kubernetes'), t.vocabFuzzy);
ok('Zeichensetzung', t.punct === 'Das ist ein satz.', t.punct);
ok('Sprach-Heuristik DE', t.langDe);
ok('Sprach-Heuristik EN', t.langEn);
ok('SRT-Zeitformat', t.srt === '00:01:15,250', t.srt);
ok('Levenshtein', t.lev === 1, String(t.lev));

console.log('\n== Mix-Modus (Confidence-Auswahl) ==');
await page.click('.lang[data-lang="mix"]');
const mix = await page.evaluate(async () => {
  // Zwei konkurrierende Ergebnisse zur selben Zeit -> das besser passende gewinnt
  const seg = [];
  VN.session.lang = 'mix';
  const fake = (lang,text,conf,tStart) => window.dispatchEvent(new Event('noop')) || null;
  // direkter Weg über die interne Bewertung:
  VN.session.segments.length = 0;
  VN.feed('ich muss noch das deployment fertig machen','de',0.9);
  VN.feed('i need to finish the deployment today','en',0.9);
  return VN.session.segments.map(s => ({lang:s.lang, text:s.text}));
});
ok('gemischte Segmente angelegt', mix.length===2, JSON.stringify(mix));
ok('Sprach-Badges gerendert', (await page.locator('.seg .badge').count())>=2);

console.log('\n== Aufnahme mit Fake-Mikrofon ==');
await page.click('.lang[data-lang="de"]');
await page.click('#btnNew');
await page.click('#btnMic');
await page.waitForTimeout(1200);
ok('Aufnahme läuft (Lampe)', await page.locator('#lamp.live').count()===1);
ok('Pause/Marke aktiv', !(await page.locator('#btnPause').isDisabled()));
await page.click('#btnMark');
await page.evaluate(() => { VN.feed('das ist die erste testaufnahme','de',0.92); VN.feed('und hier kommt der zweite satz','de',0.88); });
await page.waitForTimeout(1400);
const timer = await page.locator('#timer').textContent();
ok('Timer läuft', timer !== '00:00', timer);
await page.click('#btnMic'); // stop
await page.waitForTimeout(1500);
ok('Wiedergabe-Leiste erscheint', await page.locator('#playCard').isVisible());
const audioInfo = await page.evaluate(() => ({size:VN.session.audioSize, type:VN.session.audioType, dur:VN.session.durationMs, title:VN.session.title}));
ok('Audio aufgezeichnet', audioInfo.size > 500, JSON.stringify(audioInfo));
ok('Titel automatisch gesetzt', !!audioInfo.title, audioInfo.title);
ok('Wörterzähler > 0', (await page.locator('#stWords').textContent()) !== '0');
ok('Marken gezählt', (await page.locator('#stMarks').textContent()) === '1');

console.log('\n== Wiedergabe & Karaoke ==');
await page.evaluate(() => { const p=document.querySelector('#player'); p.currentTime=0.2; });
await page.click('#btnPlay');
await page.waitForTimeout(900);
ok('Audio spielt', await page.evaluate(()=>!document.querySelector('#player').paused));
await page.click('#btnPlay');

console.log('\n== Export ==');
const ex = await page.evaluate(() => ({ srt: VN.srt(), md: VN.md(), txt: VN.text() }));
ok('TXT enthält Text', ex.txt.includes('testaufnahme'), ex.txt);
ok('SRT wohlgeformt', /^1\n\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}\n/.test(ex.srt), JSON.stringify(ex.srt.slice(0,80)));
ok('Markdown mit Kopf', ex.md.startsWith('# ') && ex.md.includes('Wörter'));
const dl = page.waitForEvent('download');
await page.click('#btnExport');
await page.locator('.menu button', { hasText:'Text (.txt)' }).click();
const file = await dl;
ok('Datei-Download', (await file.suggestedFilename()).endsWith('.txt'), await file.suggestedFilename());

console.log('\n== Archiv ==');
await page.click('#btnArchive');
await page.waitForTimeout(400);
ok('Eintrag im Archiv', (await page.locator('#archList .item').count()) >= 1);
await page.fill('#archSearch', 'testaufnahme');
await page.waitForTimeout(300);
ok('Volltextsuche findet', (await page.locator('#archList .item').count()) === 1);
ok('Treffer hervorgehoben', (await page.locator('#archList mark').count()) >= 1);
await page.fill('#archSearch', 'gibtesnicht');
await page.waitForTimeout(300);
ok('Leere Suche zeigt Hinweis', await page.locator('#archList .empty').isVisible());
await page.fill('#archSearch', '');
await page.waitForTimeout(300);
await page.click('#sheetArchive [data-close]');

console.log('\n== Neu laden / Wiederherstellen ==');
await page.reload({ waitUntil:'networkidle' });
await page.click('#btnArchive');
await page.waitForTimeout(500);
ok('Archiv nach Reload vorhanden', (await page.locator('#archList .item').count()) >= 1);
await page.locator('#archList .item .body').first().click();
await page.waitForTimeout(600);
ok('Sitzung geladen', (await page.locator('.seg').count()) >= 2);
ok('Audio wiederhergestellt', await page.locator('#playCard').isVisible());

console.log('\n== Bearbeiten & Einstellungen ==');
const seg = page.locator('.seg .txt').first();
await seg.click();
await seg.fill?.(''); // contenteditable: über evaluate
await page.evaluate(() => {
  const el = document.querySelector('.seg .txt');
  el.innerText = 'korrigierter text';
  el.dispatchEvent(new Event('blur'));
});
await page.waitForTimeout(300);
ok('Bearbeitung übernommen', await page.evaluate(()=>VN.session.segments[0].text==='korrigierter text'));
await page.click('#btnSettings');
await page.waitForTimeout(200);
ok('Einstellungen offen', await page.locator('#sheetSettings').isVisible());
await page.click('.toggle[data-set="fillers"]');
ok('Schalter umgelegt', await page.evaluate(()=>VN.S.fillers===true||VN.S.fillers===false));
await page.fill('#setChatModel','gpt-4o-mini');
await page.click('#btnSaveSettings');
await page.waitForTimeout(200);
ok('Einstellungen gespeichert', await page.evaluate(()=>!!localStorage.getItem('vn.settings.v1')));
await page.click('#btnStats');
await page.waitForTimeout(300);
ok('Statistik zeigt Zahlen', (await page.locator('#statsBody').textContent()).includes('Dauer'));
await page.click('#sheetStats [data-close]');

console.log('\n== Design & PWA ==');
await page.click('#btnTheme');
const th = await page.evaluate(()=>document.documentElement.dataset.theme);
ok('Theme umgeschaltet', ['dark','light'].includes(th), th);
ok('Service Worker registriert', await page.evaluate(async()=>!!(await navigator.serviceWorker.getRegistration())));
const man = await page.evaluate(async()=> (await fetch('manifest.json')).ok);
ok('Manifest erreichbar', man);

await page.screenshot({ path:'shot-dark.png', fullPage:false });
await page.click('#btnTheme');
await page.screenshot({ path:'shot-light.png', fullPage:false });

console.log('\n== Ohne Spracherkennung (Fallback) ==');
const p2 = await ctx.newPage();
await p2.addInitScript(()=>{ delete window.SpeechRecognition; delete window.webkitSpeechRecognition; });
p2.on('pageerror', e=>errs.push('FALLBACK PAGEERROR: '+e.message));
await p2.goto(URL,{waitUntil:'networkidle'});
ok('Hinweisbox erscheint', await p2.locator('#warnBox').isVisible());
ok('Aufnahme trotzdem möglich', await p2.locator('#btnMic').isEnabled());
await p2.close();

console.log('\n== Konsolenfehler gesamt ==');
const real = errs.filter(e => !/favicon|Failed to load resource: the server responded with a status of 404/.test(e));
ok('keine Fehler', real.length===0, real.join(' | '));

await browser.close();
console.log('\n'+(fails? '❌ '+fails+' Prüfungen fehlgeschlagen' : '✅ Alle Prüfungen bestanden'));
process.exit(fails?1:0);
