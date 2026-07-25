import { chromium } from 'playwright';
let fails = 0;
const ok = (n, c, x='') => { console.log((c?'  ✓ ':'  ✗ ')+n+(c?'':' — '+x)); if(!c) fails++; };

const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined });
const ctx = await browser.newContext({ permissions:['microphone'], viewport:{width:412,height:900} });
await ctx.addInitScript(() => {
  const ac = new AudioContext();
  navigator.mediaDevices.getUserMedia = async () => {
    const osc=ac.createOscillator(), g=ac.createGain(), d=ac.createMediaStreamDestination();
    osc.frequency.value=210; g.gain.value=.35; osc.connect(g); g.connect(d); osc.start(); return d.stream;
  };
});
const page = await ctx.newPage();
page.on('pageerror', e => { console.log('PAGEERROR', e.message); fails++; });
page.on('dialog', d => d.accept());
await page.goto('http://localhost:8765/transcribe/', { waitUntil:'networkidle' });

await page.evaluate(() => {
  Object.assign(VN.S, { apiKey:'sk-test-123', baseUrl:'http://localhost:8766/v1',
                        model:'whisper-1', chatModel:'gpt-4o-mini', vocab:'Kubernetes\ndeployment' });
});

console.log('\n== Aufnahme für den Pro-Lauf ==');
await page.click('#btnMic');
await page.waitForTimeout(2500);
await page.evaluate(() => VN.feed('ich muss noch das deployment fertig machen','de',0.8));
await page.click('#btnMic');
await page.waitForTimeout(1500);

console.log('\n== Pro-Transkript (whisper-1, mit Zeitstempeln) ==');
await page.click('#btnPro');
await page.waitForFunction(() => !!VN.session.pro, null, { timeout:20000 }).catch(()=>{});
const pro = await page.evaluate(() => VN.session.pro && VN.session.pro.map(s=>({t:s.text,l:s.lang,a:s.tStart,b:s.tEnd,src:s.source})));
ok('Pro-Segmente erzeugt', !!pro && pro.length===2, JSON.stringify(pro));
ok('Zeitstempel übernommen', pro && pro[1].a===2.4 && pro[1].b===5.1, JSON.stringify(pro&&pro[1]));
ok('Sprache je Segment erkannt', pro && pro[0].l==='de' && pro[1].l==='en', JSON.stringify(pro&&pro.map(s=>s.l)));
ok('Ansicht auf PRO umgestellt', await page.evaluate(()=>VN.session.view==='pro'));
ok('PRO-Badge sichtbar', (await page.locator('.badge.pro').count())>=1);
ok('SRT nutzt Pro-Zeiten', (await page.evaluate(()=>VN.srt())).includes('00:00:02,400 --> 00:00:05,100'));

const req = await (await fetch('http://localhost:8766/__seen')).json();
const tr = req.find(r=>r.url.includes('transcriptions'));
ok('Bearer-Key gesendet', tr.auth === 'Bearer sk-test-123', tr.auth);
ok('Modell gesendet', tr.model === 'whisper-1', tr.model);
ok('Sprache gesetzt (de)', tr.language === 'de', String(tr.language));
ok('Wortschatz als Prompt', /Kubernetes/.test(tr.prompt||''), String(tr.prompt));
ok('verbose_json angefordert', tr.format === 'verbose_json', tr.format);
ok('Audiodatei angehängt', tr.bytes > 1000 && /\.(webm|m4a|wav)$/.test(tr.filename||''), tr.filename+' '+tr.bytes);

console.log('\n== Live/Pro umschalten ==');
await page.click('#btnView');
ok('zurück auf Live', await page.evaluate(()=>VN.session.view==='live'));
await page.click('#btnView');

console.log('\n== Mix-Modus lässt das Modell entscheiden ==');
await page.evaluate(async () => { VN.session.lang='mix'; await VN.pro.runPro(); });
await page.waitForTimeout(800);
const seen2 = await (await fetch('http://localhost:8766/__seen')).json();
const last = seen2.filter(r=>r.url.includes('transcriptions')).pop();
ok('kein language-Feld im Mix', last.language === undefined, String(last.language));

console.log('\n== Ohne Zeitstempel (gpt-4o-transcribe) ==');
await page.evaluate(async () => { VN.S.model='gpt-4o-transcribe'; VN.session.lang='de'; VN.session.pro=null; await VN.pro.runPro(); });
await page.waitForTimeout(600);
const pro2 = await page.evaluate(()=>VN.session.pro.map(s=>({t:s.text,a:s.tStart,b:s.tEnd})));
ok('Text in Sätze zerlegt', pro2.length===2, JSON.stringify(pro2));
ok('Zeiten über die Dauer verteilt', pro2[0].a===0 && pro2[1].b>pro2[0].b && pro2[1].b<=Math.ceil(await page.evaluate(()=>VN.session.durationMs/1000))+0.1, JSON.stringify(pro2));

console.log('\n== KI-Nachbearbeitung ==');
await page.click('#btnAI');
await page.locator('.menu button', { hasText:'Zusammenfassung' }).click();
await page.waitForTimeout(700);
ok('KI-Ergebnis angezeigt', (await page.locator('#aiOut').textContent()).includes('To-dos'));
const chat = (await (await fetch('http://localhost:8766/__seen')).json()).find(r=>r.url.includes('chat'));
ok('Text-Modell gesendet', chat.model==='gpt-4o-mini', chat.model);
ok('Transkript als Eingabe', /deployment/.test(chat.user), chat.user);
await page.click('#btnAiApply');
await page.waitForTimeout(300);
ok('KI-Text übernommen', (await page.evaluate(()=>VN.text())).includes('Kurzfassung'));

console.log('\n== Lange Aufnahme: WAV-Stückelung ==');
const chunk = await page.evaluate(async () => {
  const ac=new AudioContext(); const sr=ac.sampleRate;
  const buf=ac.createBuffer(1, Math.round(sr*3), sr);
  const d=buf.getChannelData(0); for(let i=0;i<d.length;i++) d[i]=Math.sin(i/40)*0.4;
  const blob=await VN.pro.sliceToWav(buf, 0.5, 2.5);
  const head=new Uint8Array(await blob.slice(0,44).arrayBuffer());
  const str=(a,b)=>String.fromCharCode(...head.slice(a,b));
  const dv=new DataView(head.buffer);
  return { type:blob.type, size:blob.size, riff:str(0,4), wave:str(8,12),
           rate:dv.getUint32(24,true), bits:dv.getUint16(34,true), ch:dv.getUint16(22,true) };
});
ok('WAV-Kopf korrekt', chunk.riff==='RIFF' && chunk.wave==='WAVE', JSON.stringify(chunk));
ok('16 kHz Mono 16 Bit', chunk.rate===16000 && chunk.ch===1 && chunk.bits===16, JSON.stringify(chunk));
ok('2 Sekunden Nutzdaten', Math.abs(chunk.size-44-2*16000*2) < 400, String(chunk.size));

console.log('\n== Fehlerbehandlung ohne Key ==');
await page.evaluate(()=>{ VN.S.apiKey=''; });
await page.click('#btnPro');
await page.waitForTimeout(400);
ok('Hinweis + Einstellungen öffnen', await page.locator('#sheetSettings').isVisible());

await browser.close();
console.log('\n'+(fails? '❌ '+fails+' Prüfungen fehlgeschlagen' : '✅ Alle Pro-Prüfungen bestanden'));
process.exit(fails?1:0);
