#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright"]
# ///

"""1000Kitap kesfet listelerinden kitap ve ISBN bilgisi toplar.

Çıktı JSONL'dir; her satır daha sonra ISBNdb aktarımına doğrudan uygundur.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import json
import re
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urljoin, urlsplit, urlunsplit

from playwright.async_api import BrowserContext, Error, Page, Response, async_playwright

BASE_URL = "https://1000kitap.com"
DEFAULT_LIST_URLS = (
    f"{BASE_URL}/kesfet/ilgi-goren-kitaplar",
    f"{BASE_URL}/kesfet/yeni-ve-populer-kitaplar",
    f"{BASE_URL}/kesfet/en-cok-okunan-kitaplar",
)
DEFAULT_OUTPUT = Path("output/books.jsonl")
DEFAULT_PROFILE = Path("output/browser-profile")
DEFAULT_STORAGE_STATE = Path("output/1000kitap-state.json")
ISBN_PATTERN = re.compile(r"(?<!\d)(?:97[89][\d -]{10,16}|\d{9}[\dXx])(?!\d)")
BOOK_URL_PATTERN = re.compile(r"/kitap/[^/?#]+--\d+(?:[/?#]|$)")
PAGE_KEYS = ("page", "sayfa", "p")
BROWSER_ARGS = ("--disable-blink-features=AutomationControlled",)
LIST_SETTLE_SECONDS = 1.5
RATE_LIMIT_WAIT_SECONDS = 60
CHALLENGE_MARKERS = (
    "cloudflare",
    "attention required",
    "verify you are human",
    "insan olduğunuzu doğrulayın",
    "just a moment",
)


def compact(text: str | None) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def text_value(value: Any) -> str | None:
    return compact(str(value)) if value is not None else None


def canonical_book_url(url: str) -> str:
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path.rstrip("/"), "", ""))


def canonical_page_url(url: str) -> str:
    parts = urlsplit(url)
    return urlunsplit(
        (parts.scheme, parts.netloc, parts.path.rstrip("/"), parts.query, "")
    )


def normalize_isbn(value: str) -> str | None:
    digits = re.sub(r"[^0-9Xx]", "", value).upper()
    if (
        len(digits) == 13
        and digits.startswith(("978", "979"))
        and sum(
            (1 if index % 2 == 0 else 3) * int(char)
            for index, char in enumerate(digits)
        )
        % 10
        == 0
    ):
        return digits
    if len(digits) == 10:
        total = sum(
            (10 - index) * (10 if char == "X" else int(char))
            for index, char in enumerate(digits)
        )
        if total % 11 == 0:
            return digits
    return None


def isbn13(value: str | None) -> str | None:
    if not value:
        return None
    if len(value) == 13:
        return value
    if len(value) != 10:
        return None
    body = "978" + value[:9]
    check = (
        10
        - sum(
            (1 if index % 2 == 0 else 3) * int(char) for index, char in enumerate(body)
        )
        % 10
    ) % 10
    return body + str(check)


def isbn_candidates(text: str) -> list[str]:
    result: list[str] = []
    for match in ISBN_PATTERN.findall(text):
        value = normalize_isbn(match)
        if value and value not in result:
            result.append(value)
    return result


def label_value(text: str, labels: tuple[str, ...]) -> str | None:
    lines = [compact(line) for line in text.splitlines() if compact(line)]
    for index, line in enumerate(lines):
        lower = line.casefold()
        for label in labels:
            marker = label.casefold()
            if lower == marker:
                return lines[index + 1] if index + 1 < len(lines) else None
            if lower.startswith(marker + ":"):
                return compact(line.split(":", 1)[1]) or (
                    lines[index + 1] if index + 1 < len(lines) else None
                )
    return None


def page_number(url: str) -> int:
    query = parse_qs(urlsplit(url).query)
    for key in PAGE_KEYS:
        if query.get(key) and query[key][0].isdigit():
            return int(query[key][0])
    return 1


def find_next_url(
    links: list[dict[str, str]], current_url: str, list_url: str
) -> str | None:
    current = page_number(current_url)
    list_path = urlsplit(list_url).path.rstrip("/")
    candidates: list[tuple[int, str]] = []
    explicit: str | None = None
    for link in links:
        href = link.get("href", "")
        text = compact(link.get("text") or link.get("aria"))
        parts = urlsplit(href)
        if parts.netloc and parts.netloc != urlsplit(list_url).netloc:
            continue
        if parts.path.rstrip("/") != list_path:
            continue
        normalized_text = text.casefold().replace("\u0307", "")
        if normalized_text in {"ileri", "sonraki", "next", ">", "›", "»"}:
            explicit = canonical_page_url(urljoin(current_url, href))
            continue
        if text.isdigit() and int(text) > current:
            candidates.append(
                (int(text), canonical_page_url(urljoin(current_url, href)))
            )
    if candidates:
        return min(candidates)[1]
    return explicit


async def page_links(page: Page) -> list[dict[str, str]]:
    return await page.locator("a").evaluate_all(
        """elements => elements.map(a => ({
            href: a.href || '',
            text: a.innerText || a.textContent || '',
            aria: a.getAttribute('aria-label') || ''
        }))"""
    )


async def page_has_challenge(page: Page) -> bool:
    text = f"{await page.title()} {await page.locator('body').inner_text()}".casefold()
    return any(marker in text for marker in CHALLENGE_MARKERS)


async def goto(
    page: Page, url: str, retries: int, wait_for_challenge: bool = False
) -> Response | None:
    for attempt in range(retries + 1):
        try:
            response = await page.goto(
                url, wait_until="domcontentloaded", timeout=45_000
            )
            status = response.status if response else 0
            if status == 403 or (wait_for_challenge and await page_has_challenge(page)):
                if wait_for_challenge:
                    await page.bring_to_front()
                    print(
                        "[challenge] Aynı sekmedeki doğrulamayı çözün; 3 dakika bekleniyor.",
                        flush=True,
                    )
                    for _ in range(180):
                        await asyncio.sleep(1)
                        if (
                            not await page_has_challenge(page)
                            and await page.locator('a[href*="/kitap/"]').count()
                        ):
                            return response
                print(f"[blocked] HTTP {status or 403}: {url}", file=sys.stderr)
                return None
            if status == 429:
                if wait_for_challenge and attempt < retries:
                    await page.bring_to_front()
                    print(
                        f"[rate-limit] Aynı sekmede {RATE_LIMIT_WAIT_SECONDS} saniye bekleniyor.",
                        flush=True,
                    )
                    await asyncio.sleep(RATE_LIMIT_WAIT_SECONDS)
                if attempt < retries:
                    if not wait_for_challenge:
                        await asyncio.sleep(2**attempt * 5)
                    continue
            if response and status >= 400:
                print(f"[http {status}] {url}", file=sys.stderr)
                return None
            return response
        except Error as error:
            if attempt >= retries:
                print(f"[error] {url}: {error}", file=sys.stderr)
                return None
            await asyncio.sleep(2**attempt)
    return None


async def discover(
    context: BrowserContext,
    list_urls: tuple[str, ...],
    max_pages: int,
    max_books: int,
    retries: int,
    wait_for_challenge: bool,
) -> list[dict[str, Any]]:
    page = await context.new_page()
    books: dict[str, dict[str, Any]] = {}
    try:
        for list_url in list_urls:
            next_url = list_url
            visited: set[str] = set()
            pages = 0
            while (
                next_url
                and next_url not in visited
                and (not max_pages or pages < max_pages)
            ):
                visited.add(next_url)
                if not await goto(page, next_url, retries, wait_for_challenge):
                    break
                await page.wait_for_timeout(LIST_SETTLE_SECONDS * 1000)
                pages += 1
                links = await page_links(page)
                for position, link in enumerate(links, start=1):
                    raw_url = canonical_book_url(
                        urljoin(page.url, link.get("href", ""))
                    )
                    if not BOOK_URL_PATTERN.search(urlsplit(raw_url).path):
                        continue
                    title = compact(link.get("text"))
                    if not title:
                        continue
                    book = books.setdefault(
                        raw_url,
                        {
                            "book_url": raw_url,
                            "title": title,
                            "rank": position,
                            "source_lists": [],
                        },
                    )
                    if list_url not in book["source_lists"]:
                        book["source_lists"].append(list_url)
                    if max_books and len(books) >= max_books:
                        return list(books.values())
                next_url = find_next_url(links, page.url, list_url)
                print(
                    f"[discover] {list_url} page={pages} total={len(books)}", flush=True
                )
    finally:
        await page.close()
    return list(books.values())


async def first_text(page: Page, selectors: tuple[str, ...]) -> str | None:
    for selector in selectors:
        locator = page.locator(selector).first
        if await locator.count():
            value = compact(await locator.inner_text(timeout=2_000))
            if value:
                return value
    return None


def jsonld_book(values: list[str]) -> dict[str, Any]:
    def walk(value: Any) -> dict[str, Any] | None:
        if isinstance(value, dict):
            kind = value.get("@type", "")
            if kind == "Book" or (isinstance(kind, list) and "Book" in kind):
                return value
            for child in value.values():
                found = walk(child)
                if found:
                    return found
        elif isinstance(value, list):
            for child in value:
                found = walk(child)
                if found:
                    return found
        return None

    for raw in values:
        try:
            found = walk(json.loads(raw))
            if found:
                return found
        except json.JSONDecodeError:
            continue
    return {}


def jsonld_name(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, dict):
        return text_value(value.get("name"))
    if isinstance(value, list):
        names = [jsonld_name(item) for item in value]
        return ", ".join(name for name in names if name) or None
    return text_value(value)


async def scrape_detail(
    page: Page,
    item: dict[str, Any],
    delay: float,
    retries: int,
    wait_for_challenge: bool,
) -> dict[str, Any] | None:
    if not await goto(page, item["book_url"], retries, wait_for_challenge):
        return None
    body = await page.locator("body").inner_text()
    data = jsonld_book(
        await page.locator('script[type="application/ld+json"]').all_text_contents()
    )
    found_isbns = isbn_candidates(str(data.get("isbn", "")) + "\n" + body)
    first_isbn = found_isbns[0] if found_isbns else None
    author = jsonld_name(data.get("author"))
    if not author:
        author_links = await page.locator('a[href*="/yazar"]').all_inner_texts()
        author = (
            compact(author_links[0])
            if author_links
            else label_value(body, ("Yazar", "Yazarlar"))
        )
    publisher = jsonld_name(data.get("publisher")) or label_value(
        body, ("Yayınevi", "Yayımcı")
    )
    pages = data.get("numberOfPages") or label_value(body, ("Sayfa Sayısı", "Sayfa"))
    record = {
        **item,
        "title": text_value(data.get("name"))
        or await first_text(page, ("h1", "h2"))
        or item["title"],
        "author": author,
        "isbn": first_isbn,
        "isbn13": isbn13(first_isbn),
        "isbn10": first_isbn if first_isbn and len(first_isbn) == 10 else None,
        "publisher": publisher,
        "publication_date": data.get("datePublished")
        or label_value(body, ("Yayın Tarihi", "Basım Tarihi", "İlk Yayın")),
        "pages": pages,
        "language": data.get("inLanguage") or label_value(body, ("Dil",)),
        "format": data.get("bookFormat") or label_value(body, ("Format", "Baskı")),
        "description": text_value(data.get("description"))
        or label_value(body, ("Açıklama", "Kitap Hakkında")),
        "cover_url": data.get("image"),
        "scraped_at": datetime.now(UTC).isoformat(),
    }
    if delay:
        await asyncio.sleep(delay)
    return record


def load_seen(path: Path) -> set[str]:
    if not path.exists():
        return set()
    seen: set[str] = set()
    with path.open(encoding="utf-8") as file:
        for line in file:
            try:
                url = json.loads(line).get("book_url")
                if url:
                    seen.add(url)
            except json.JSONDecodeError:
                continue
    return seen


def append_record(file: Any, record: dict[str, Any]) -> None:
    file.write(json.dumps(record, ensure_ascii=False) + "\n")
    file.flush()


def write_csv(jsonl_path: Path, csv_path: Path) -> None:
    fields = (
        "isbn13",
        "isbn10",
        "title",
        "author",
        "publisher",
        "publication_date",
        "pages",
        "language",
        "format",
        "book_url",
    )
    with jsonl_path.open(encoding="utf-8") as file:
        rows = [json.loads(line) for line in file if line.strip()]
    with csv_path.open("w", newline="", encoding="utf-8-sig") as file:
        writer = csv.DictWriter(file, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def self_test() -> None:
    assert normalize_isbn("978-975-363-802-9") == "9789753638029"
    assert normalize_isbn("9789753638028") is None
    assert isbn13("9753638027") == "9789753638029"
    links = [
        {
            "href": "https://1000kitap.com/kesfet/ilgi-goren-kitaplar?page=2",
            "text": "2",
            "aria": "",
        }
    ]
    assert find_next_url(
        links, "https://1000kitap.com/kesfet/ilgi-goren-kitaplar", DEFAULT_LIST_URLS[0]
    ).endswith("page=2")
    assert find_next_url(
        [{"href": "/kesfet/ilgi-goren-kitaplar?sayfa=2", "text": "İleri", "aria": ""}],
        "https://1000kitap.com/kesfet/ilgi-goren-kitaplar",
        DEFAULT_LIST_URLS[0],
    ).endswith("sayfa=2")
    assert isbn_candidates("ISBN: 978-975-363-802-9") == ["9789753638029"]
    print("self-test: ok")


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--list-url",
        action="append",
        dest="list_urls",
        help="Liste URL'si; tekrar edilebilir.",
    )
    parser.add_argument(
        "--output", type=Path, default=DEFAULT_OUTPUT, help="JSONL çıktı yolu."
    )
    parser.add_argument(
        "--profile",
        type=Path,
        default=DEFAULT_PROFILE,
        help="Kalıcı Chromium profil yolu.",
    )
    parser.add_argument(
        "--storage-state",
        type=Path,
        default=DEFAULT_STORAGE_STATE,
        help="CLI/Chrome oturum dosyası; varsa kullanılır.",
    )
    parser.add_argument(
        "--browser",
        choices=("chrome", "msedge", "bundled"),
        default="chrome",
        help="Kurulu tarayıcı kanalı; bundled Playwright Chromium kullanır.",
    )
    parser.add_argument(
        "--max-books", type=int, default=0, help="Toplam kitap sınırı; 0 = sınırsız."
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=0,
        help="Her liste için sayfa sınırı; 0 = sınırsız.",
    )
    parser.add_argument(
        "--delay", type=float, default=0.75, help="Detay istekleri arasındaki saniye."
    )
    parser.add_argument(
        "--retries", type=int, default=2, help="429/ağ hatası tekrar sayısı."
    )
    parser.add_argument(
        "--headed",
        action="store_true",
        help="Görünür Chromium kullan; Cloudflare challenge için gerekebilir.",
    )
    parser.add_argument(
        "--csv", action="store_true", help="JSONL yanında aynı adda CSV de üret."
    )
    parser.add_argument(
        "--self-test", action="store_true", help="Yerel parser kontrollerini çalıştır."
    )
    return parser.parse_args()


async def run(args: argparse.Namespace) -> None:
    if args.delay < 0 or args.retries < 0:
        raise SystemExit("delay >= 0 ve retries >= 0 olmalı.")
    list_urls = tuple(args.list_urls or DEFAULT_LIST_URLS)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.profile.parent.mkdir(parents=True, exist_ok=True)
    args.storage_state.parent.mkdir(parents=True, exist_ok=True)
    seen = load_seen(args.output)
    async with async_playwright() as playwright:
        channel = None if args.browser == "bundled" else args.browser
        browser = None
        if args.storage_state.exists():
            browser = await playwright.chromium.launch(
                headless=not args.headed, channel=channel, args=list(BROWSER_ARGS)
            )
            context = await browser.new_context(
                storage_state=str(args.storage_state), locale="tr-TR"
            )
        else:
            context = await playwright.chromium.launch_persistent_context(
                str(args.profile),
                headless=not args.headed,
                locale="tr-TR",
                channel=channel,
                args=list(BROWSER_ARGS),
            )
        try:
            discovered = await discover(
                context,
                list_urls,
                args.max_pages,
                args.max_books,
                args.retries,
                args.headed,
            )
            if not discovered:
                raise SystemExit(
                    "Kitap listesi alınamadı. 1000Kitap 403/Cloudflare döndürüyorsa "
                    "--headed ile görünür Chrome açıp challenge'ı çözün."
                )
            pending = [item for item in discovered if item["book_url"] not in seen]
            if args.max_books:
                pending = pending[: args.max_books]
            print(
                f"[queue] unique={len(discovered)} pending={len(pending)} existing={len(seen)}",
                flush=True,
            )
            detail_page = await context.new_page()
            try:
                with args.output.open("a", encoding="utf-8") as file:
                    target = len(seen) + len(pending)
                    for index, item in enumerate(pending, start=1):
                        record = await scrape_detail(
                            detail_page, item, args.delay, args.retries, args.headed
                        )
                        if record:
                            append_record(file, record)
                            seen.add(record["book_url"])
                        if index % 10 == 0 or index == len(pending):
                            print(f"[details] saved={len(seen)}/{target}", flush=True)
            finally:
                await detail_page.close()
        finally:
            await context.storage_state(path=str(args.storage_state))
            await context.close()
            if browser:
                await browser.close()
    if args.csv:
        csv_path = args.output.with_suffix(".csv")
        write_csv(args.output, csv_path)
        print(f"[done] {csv_path}")
    print(f"[done] {args.output} records={len(seen)}")


def main() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    args = arguments()
    if args.self_test:
        self_test()
        return
    try:
        asyncio.run(run(args))
    except Error as error:
        print(
            f"Playwright çalışmadı: {error}\nChromium kur: uv run --with playwright python -m playwright install chromium",
            file=sys.stderr,
        )
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
