export function parseQuery({ q, page }) {
  return { ok: true, q: q ?? '', page: Number(page) || 1 };
}

export function search({ q, page }) {
  return { items: [], total: 0, q, page };
}
