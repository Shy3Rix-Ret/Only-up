/* Nachbau der OpenAI-Endpunkte, um den Pro-Modus ohne echten Key zu prüfen. */
import http from 'node:http';

const seen = [];
const server = http.createServer((req, res) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': 'POST,OPTIONS',
    'Content-Type': 'application/json'
  };
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }

  const bufs = [];
  req.on('data', d => bufs.push(d));
  req.on('end', () => {
    const body = Buffer.concat(bufs);
    const text = body.toString('latin1');
    if (req.url.endsWith('/audio/transcriptions')) {
      const field = n => (text.match(new RegExp('name="' + n + '"\\r\\n\\r\\n([^\\r]*)')) || [])[1];
      const rec = {
        url: req.url, auth: req.headers.authorization, bytes: body.length,
        model: field('model'), language: field('language'),
        prompt: field('prompt'), format: field('response_format'),
        filename: (text.match(/filename="([^"]+)"/) || [])[1]
      };
      seen.push(rec);
      const verbose = rec.format === 'verbose_json';
      res.writeHead(200, cors);
      return res.end(JSON.stringify(verbose ? {
        text: 'Ich muss noch das deployment fertig machen. And then I will review the pull request.',
        segments: [
          { start: 0.0, end: 2.4, text: ' Ich muss noch das deployment fertig machen.' },
          { start: 2.4, end: 5.1, text: ' And then I will review the pull request.' }
        ]
      } : {
        text: 'Ich muss noch das deployment fertig machen. And then I will review the pull request.'
      }));
    }
    if (req.url.endsWith('/chat/completions')) {
      const j = JSON.parse(body.toString('utf8'));
      seen.push({ url: req.url, model: j.model, system: j.messages[0].content.slice(0, 40), user: j.messages[1].content });
      res.writeHead(200, cors);
      return res.end(JSON.stringify({ choices: [{ message: { content: 'Kurzfassung\nDas Deployment ist offen.\n\nTo-dos\n- Deployment fertig machen' } }] }));
    }
    if (req.url === '/__seen') { res.writeHead(200, cors); return res.end(JSON.stringify(seen)); }
    res.writeHead(404, cors); res.end('{}');
  });
});
server.listen(8766, () => console.log('mock api on 8766'));
