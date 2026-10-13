# 1000Kitap Scraper

Collects book titles, authors, and ISBNs from 1000Kitap into JSONL. By default, it scans two popular lists and the most-read list, recording each book URL only once.

```powershell
cd C:\Kargalar\Projeler\Flutter\booklibrary\bookdatascraping\1k
uv run --script scrape_1000kitap.py --self-test
uv run --with playwright python -m playwright install chromium
uv run --script scrape_1000kitap.py --max-books 20 --csv
```

Omit `--max-books` for a full scan. Output is written to `output/books.jsonl` and, when `--csv` is set, `output/books.csv`. Subsequent runs skip existing `book_url` records. The Chromium profile is stored in `output/browser-profile`, and CLI session state is stored in `output/1000kitap-state.json`.

In headed mode, book details open sequentially in one tab. If a human verification page appears, complete it in that tab. The script then resumes automatically without opening extra detail tabs.

Cloudflare `403` responses are not bypassed automatically. Try a visible Chrome session with `uv run --script scrape_1000kitap.py --headed`; use `--browser bundled` if needed. Resolve any challenge manually. The script does not automate logins, proxies, or CAPTCHAs.
