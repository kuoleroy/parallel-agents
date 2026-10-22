export function parseQuery({ q, page }) {
  if (page !== undefined && page !== null && page !== '' && !/^[1-9][0-9]*$/.test(String(page))) {
    return { ok: false, error: 'page must be a positive integer' };
  }
  return { ok: true, q: q ?? '', page: page ? Number(page) : 1 };
}

export function search({ q, page }) {
  return { items: [], total: 0, q, page };
}
