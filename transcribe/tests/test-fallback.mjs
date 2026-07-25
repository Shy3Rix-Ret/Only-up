/* Prüft das Verhalten, wenn die Live-Erkennung nichts liefert (typisch iPhone/Safari):
   Aufnahme muss erhalten bleiben, Hilfe erscheinen, Nur-Text-Modus funktionieren. */
import { chromium } from 'playwright';
let fails = 0;
const ok = (n,c,x='') => { console.log((c?'  ✓ ':'  ✗ ')+n+(c?'':' — '+x)); if(!c) fails++; };
const URL = 'http://localhost:8765/transcribe/';

const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined });

/* ---------- 1) Erkennung liefert nichts, Mitschnitt läuft ---------- */
{
  const ctx = await browser.newContext({ permissions:['microphone'], viewport:{width:412,height:900} });
  await ctx.addInitScript(() => {
    const ac = new AudioContext();
    navigator.mediaDevices.getUserMedia = async () => {
      const o=ac.createOscillator(), g=ac.createGain(), d=ac.createMediaStreamDestination();
      o.frequency.value=210; g.gain.value=.4; o.connect(g); g.connect(d); o.start(); return d.stream;
    };
    /* Erkenner, der nie ein Ergebnis liefert — genau wie Safari mit belegtem Mikrofon */
    class DeadSR{ start(){ this.onstart&&this.onstart(); } stop(){ this.onend&&this.onend(); } abort(){ this.onend&&this.onend(); } }
    window.SpeechRecognition = window.webkitSpeechRecognition = DeadSR;
  });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR', e.message); fails++; });
  page.on('dialog', d => d.accept());
  await page.goto(URL, { waitUntil:'networkidle' });

  console.log('\n== Erkennung stumm, Aufnahme läuft ==');
  await page.click('#btnMic');
  await page.waitForTimeout(11000);           // über die Wächter-Schwelle hinaus
  ok('Hinweis erscheint während der Aufnahme', await page.locator('#hintBox').isVisible());
  ok('Statuszeile meldet fehlende Ergebnisse', /keine Ergebnisse/.test(await page.locator('#engStatus').textContent()),
     await page.locator('#engStatus').textContent());
  await page.click('#btnMic');
  await page.waitForTimeout(2000);

  const s = await page.evaluate(() => ({ size:VN.session.audioSize, title:VN.session.title, segs:VN.session.segments.length }));
  ok('Aufnahme wurde NICHT verworfen', s.size > 1000, JSON.stringify(s));
  ok('Sitzung hat einen Titel', !!s.title, s.title);
  ok('Wiedergabe möglich', await page.locator('#playCard').isVisible());
  ok('Hilfe statt leerem Transkript', (await page.locator('#transcript').textContent()).includes('Die Aufnahme ist gespeichert'));
  ok('Pro-Knopf verfügbar', await page.locator('#btnPro').isVisible());
  ok('Audio-Export möglich', await page.evaluate(()=>!!VN.pro.blob));

  const stored = await page.evaluate(async () => {
    const list = await VN.DB.all('sessions'); const au = await VN.DB.all('audio');
    return { sessions:list.length, audio:au.length, audioBytes:au[0]&&au[0].blob.size };
  });
  ok('im Archiv gespeichert (mit Audio)', stored.sessions===1 && stored.audio===1 && stored.audioBytes>1000, JSON.stringify(stored));

  console.log('\n== Diagnose ==');
  await page.click('#transcript >> text=🔬 Diagnose');
  await page.waitForTimeout(400);
  const diag = await page.locator('#diagBody').textContent();
  ok('Diagnose zeigt Kernwerte', /Spracherkennung vorhanden/.test(diag) && /Aufnahme-Modus/.test(diag) && /Mikrofon-Spitzenpegel/.test(diag), diag.slice(0,120));
  ok('Diagnose kennt den Pegel', !/noch nicht gemessen/.test(diag), diag.match(/Mikrofon-Spitzenpegel.*/)[0]);
  await ctx.close();
}

/* ---------- 2) Nur-Text-Modus: kein Mitschnitt, Erkennung zuerst ---------- */
{
  const ctx = await browser.newContext({ permissions:['microphone'], viewport:{width:412,height:900} });
  await ctx.addInitScript(() => {
    window.__order = [];
    const ac = new AudioContext();
    navigator.mediaDevices.getUserMedia = async () => {
      window.__order.push('getUserMedia');
      const o=ac.createOscillator(), d=ac.createMediaStreamDestination(); o.connect(d); o.start(); return d.stream;
    };
    class FakeSR{
      constructor(){ this.lang='de-DE'; FakeSR.all.push(this); }
      start(){ window.__order.push('recognition:'+this.lang); this.running=true; this.onstart&&this.onstart(); }
      stop(){ this.running=false; this.onend&&this.onend(); }
      abort(){ this.running=false; this.onend&&this.onend(); }
      emit(t,c){ this.onresult&&this.onresult({resultIndex:0,results:Object.assign([Object.assign([{transcript:t,confidence:c}],{isFinal:true,length:1})],{length:1})}); }
    }
    FakeSR.all=[]; window.SpeechRecognition=window.webkitSpeechRecognition=FakeSR; window.__FakeSR=FakeSR;
  });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR', e.message); fails++; });
  page.on('dialog', d => d.accept());
  await page.goto(URL, { waitUntil:'networkidle' });

  console.log('\n== Reihenfolge: Erkennung vor Mikrofon (Safari-Geste) ==');
  await page.click('#btnMic');
  await page.waitForTimeout(800);
  const order = await page.evaluate(()=>window.__order.slice());
  ok('Erkennung startet vor getUserMedia', order[0].startsWith('recognition'), JSON.stringify(order));
  await page.click('#btnMic');
  await page.waitForTimeout(1200);

  console.log('\n== Nur-Text-Modus ==');
  await page.click('.mode[data-cap="text"]');
  ok('Modus aktiv', await page.evaluate(()=>VN.S.capture==='text'));
  ok('Hinweis erklärt den Modus', (await page.locator('#capHint').textContent()).includes('ohne Audio'));
  await page.evaluate(()=>window.__order.length=0);
  await page.click('#btnMic');
  await page.waitForTimeout(700);
  ok('kein Mikrofon-Mitschnitt angefordert', !(await page.evaluate(()=>window.__order.includes('getUserMedia'))),
     JSON.stringify(await page.evaluate(()=>window.__order)));
  await page.evaluate(()=>window.__FakeSR.all.at(-1).emit('das ist reiner live text ohne mitschnitt',.9));
  await page.waitForTimeout(1400);
  await page.click('#btnMic');
  await page.waitForTimeout(1200);
  const t = await page.evaluate(()=>({ text:VN.text(), size:VN.session.audioSize }));
  ok('Text ist da', t.text.toLowerCase().includes('reiner live text'), t.text);
  ok('kein Audio gespeichert', !t.size, String(t.size));
  ok('Sitzung im Archiv', await page.evaluate(async()=>(await VN.DB.all('sessions')).length>=1));

  console.log('\n== Nur-Audio-Modus ==');
  await page.click('#btnNew');
  await page.click('.mode[data-cap="audio"]');
  await page.evaluate(()=>window.__order.length=0);
  await page.click('#btnMic');
  await page.waitForTimeout(900);
  const o2 = await page.evaluate(()=>window.__order.slice());
  ok('nur Mikrofon, keine Erkennung', o2.includes('getUserMedia') && !o2.some(x=>x.startsWith('recognition')), JSON.stringify(o2));
  ok('Statuszeile erklärt den Modus', (await page.locator('#engStatus').textContent()).includes('Nur Mitschnitt'));
  await page.click('#btnMic');
  await page.waitForTimeout(1600);
  ok('Aufnahme ohne Text bleibt erhalten', await page.evaluate(()=>VN.session.audioSize>500));
  await ctx.close();
}

await browser.close();
console.log('\n'+(fails? '❌ '+fails+' Prüfungen fehlgeschlagen' : '✅ Alle Fallback-Prüfungen bestanden'));
process.exit(fails?1:0);
