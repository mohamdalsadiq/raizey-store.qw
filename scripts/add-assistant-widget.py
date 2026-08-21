from pathlib import Path

root = Path(__file__).resolve().parents[1]
pages = [
    "index.html", "category.html", "product.html", "search.html", "cart.html",
    "my-orders.html", "account.html", "receipt.html", "wallet.html",
    "notifications.html", "referrals.html", "checkout-v2.html", "checkout.html",
]
needle = '<script src="assets/js/raizey-assistant.js"></script>'
for name in pages:
    path = root / name
    text = path.read_text(encoding="utf-8")
    if needle in text:
        continue
    marker = "</body>"
    if marker not in text:
        raise SystemExit(f"missing body marker: {name}")
    text = text.replace(marker, f"  {needle}\n{marker}", 1)
    path.write_text(text, encoding="utf-8")
    print(f"updated {name}")
