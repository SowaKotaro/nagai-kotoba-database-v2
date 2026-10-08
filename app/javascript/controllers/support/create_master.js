// マスタ(ジャンル・エンティティ型など)をその場で追加する POST。inline_add(注釈フォームの「その場追加」)と
// genre_picker(ジャンルの段階表示の「その場追加」)が使う。成否と理由を必ず返す({record, existing} または {error})。
export async function createMaster(url, body, labels) {
  let response
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify(body)
    })
  } catch {
    return { error: labels.network_error }
  }

  // セッション切れだとログイン画面の HTML が返る(200 だが JSON ではない)。
  const data = await response.json().catch(() => null)
  if (!data) return { error: labels.unexpected_response }
  if (response.ok) return { record: data, existing: Boolean(data.existing) }

  const errors = Array.isArray(data.errors) ? data.errors.join(" / ") : ""
  return { error: errors || labels.failed.replace("%{status}", response.status) }
}

function csrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]')
  return meta ? meta.content : ""
}
