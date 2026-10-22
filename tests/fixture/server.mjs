import http from 'node:http';
import { parseQuery, search } from './src/api/search.js';

const PORT = Number(process.env.PORT || 3000);

function json(res, code, body) {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

http
  .createServer((req, res) => {
    const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
    if (url.pathname === '/api/health') {
      json(res, 200, { ok: true });
      return;
    }
    if (url.pathname === '/api/items') {
      const parsed = parseQuery({
        q: url.searchParams.get('q'),
        page: url.searchParams.get('page'),
      });
      if (!parsed.ok) {
        json(res, 400, { code: 'INVALID_QUERY', message: parsed.error });
        return;
      }
      json(res, 200, search(parsed));
      return;
    }
    json(res, 404, { code: 'NOT_FOUND', message: 'no such route' });
  })
  .listen(PORT, '127.0.0.1');
