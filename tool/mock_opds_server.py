#!/usr/bin/env python3
"""Run a small local OPDS catalog for manual app testing.

Examples:
  python3 tool/mock_opds_server.py
  python3 tool/mock_opds_server.py --port 8765 --username test --password test

The server only exposes synthetic EPUB files generated in memory. It is
intended for local development and does not proxy or aggregate book sources.
"""

from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
from html import escape
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
from pathlib import PurePosixPath
import socket
from urllib.parse import parse_qs, quote, urlparse
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile


BOOKS = (
    {
        "id": "opds-welcome",
        "slug": "opds-welcome.epub",
        "title": "远程导入测试：OPDS 入门",
        "author": "开卷测试组",
        "summary": "用于验证 OPDS 目录浏览、下载队列和 EPUB 导入流程的测试书。",
        "body": "这是一本由开卷本地测试服务动态生成的 EPUB。\n\n你可以用它验证目录浏览、搜索、选择下载、队列以及导入书库。",
    },
    {
        "id": "reading-notes",
        "slug": "reading-notes.epub",
        "title": "远程导入测试：阅读笔记",
        "author": "开卷测试组",
        "summary": "第二本测试书，用于验证多选下载和按顺序导入。",
        "body": "第二本测试书已经准备好。\n\n请在 OPDS 页面中同时选择这本书和其他书目，然后点击开始下载。",
    },
    {
        "id": "comic-import",
        "slug": "comic-import.epub",
        "title": "远程导入测试：图文书",
        "author": "开卷测试组",
        "summary": "包含插图的 reflow EPUB 测试样例。",
        "body": "这本书包含一个内嵌 SVG 图形，用于验证带图片的 reflow EPUB 仍然进入图书阅读器。",
    },
    {
        "id": "searchable-catalog",
        "slug": "searchable-catalog.epub",
        "title": "远程导入测试：搜索结果",
        "author": "开卷测试组",
        "summary": "用于验证 OPDS 搜索入口和搜索结果导入。",
        "body": "搜索关键词“搜索结果”即可找到这本测试书。",
    },
    {
        "id": "page-two",
        "slug": "page-two.epub",
        "title": "远程导入测试：第二页",
        "author": "开卷测试组",
        "summary": "分页目录中的测试书目。",
        "body": "这本书位于第二页，用于验证 OPDS next 分页链接。",
    },
)


def now_text() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def xml_text(value: str) -> str:
    return escape(value, quote=False)


def make_epub(book: dict[str, str]) -> bytes:
    title = xml_text(book["title"])
    author = xml_text(book["author"])
    body = "\n".join(
        f"<p>{xml_text(paragraph)}</p>"
        for paragraph in book["body"].split("\n\n")
    )
    image_markup = ""
    image_file = None
    if book["id"] == "comic-import":
        image_file = b"""<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360"><rect width="640" height="360" fill="#f5eee5"/><circle cx="320" cy="150" r="72" fill="#f08b52"/><path d="M160 270h320" stroke="#263238" stroke-width="12" stroke-linecap="round"/><text x="320" y="315" text-anchor="middle" font-family="sans-serif" font-size="24" fill="#263238">OPDS EPUB TEST</text></svg>"""
        image_markup = '<p><img src="images/test.svg" alt="OPDS 测试插图" /></p>'

    content = f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>{title}</title><meta charset="utf-8" /></head>
  <body><h1>{title}</h1><p>作者：{author}</p>{body}{image_markup}</body>
</html>
"""
    opf_items = '<item id="content" href="text.xhtml" media-type="application/xhtml+xml" />'
    if image_file is not None:
        opf_items += '<item id="test-image" href="images/test.svg" media-type="image/svg+xml" />'
    opf = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">{book["id"]}</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:creator>{author}</dc:creator>
    <dc:language>zh-CN</dc:language>
  </metadata>
  <manifest>{opf_items}</manifest>
  <spine><itemref idref="content" /></spine>
</package>
"""
    container = """<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml" /></rootfiles>
</container>
"""

    output = BytesIO()
    with ZipFile(output, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=ZIP_STORED)
        archive.writestr("META-INF/container.xml", container, compress_type=ZIP_DEFLATED)
        archive.writestr("OEBPS/content.opf", opf, compress_type=ZIP_DEFLATED)
        archive.writestr("OEBPS/text.xhtml", content, compress_type=ZIP_DEFLATED)
        if image_file is not None:
            archive.writestr("OEBPS/images/test.svg", image_file, compress_type=ZIP_DEFLATED)
    return output.getvalue()


EPUBS = {book["slug"]: make_epub(book) for book in BOOKS}


def feed_header(base_url: str) -> str:
    return f"""<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:kaijuan:mock-opds</id>
  <title>开卷本地 OPDS 测试目录</title>
  <updated>{now_text()}</updated>
  <link rel="self" href="{base_url}/opds" type="application/atom+xml;profile=opds-catalog" />
  <link rel="start" href="{base_url}/opds" type="application/atom+xml;profile=opds-catalog" />
  <link rel="search" href="{base_url}/opds/search?q={{searchTerms}}" type="application/atom+xml;profile=opds-catalog" />
"""


def navigation_entry(base_url: str) -> str:
    return f"""  <entry>
    <title>示例书目（分页）</title>
    <id>urn:kaijuan:mock-opds:page-two</id>
    <content type="text">打开第二页测试分页目录。</content>
    <link rel="subsection" href="{base_url}/opds/catalog?page=2" type="application/atom+xml;profile=opds-catalog" />
  </entry>
"""


def book_entry(base_url: str, book: dict[str, str]) -> str:
    return f"""  <entry>
    <title>{xml_text(book["title"])}</title>
    <id>urn:kaijuan:mock-opds:{book["id"]}</id>
    <author><name>{xml_text(book["author"])}</name></author>
    <summary>{xml_text(book["summary"])}</summary>
    <link rel="http://opds-spec.org/acquisition/open-access" href="{base_url}/books/{quote(book["slug"])}" type="application/epub+zip" />
  </entry>
"""


def render_feed(base_url: str, books: tuple[dict[str, str], ...], *, page: int) -> bytes:
    body = feed_header(base_url)
    if page == 1:
        body += navigation_entry(base_url)
    body += "".join(book_entry(base_url, book) for book in books)
    if page == 1:
        body += f'  <link rel="next" href="{base_url}/opds/catalog?page=2" type="application/atom+xml;profile=opds-catalog" />\n'
    body += "</feed>\n"
    return body.encode("utf-8")


class MockOpdsHandler(BaseHTTPRequestHandler):
    server_version = "KaijuanMockOPDS/1.0"

    def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        if not self.authorized():
            self.send_response(HTTPStatus.UNAUTHORIZED)
            self.send_header("WWW-Authenticate", 'Basic realm="Kaijuan Mock OPDS"')
            self.end_headers()
            return

        parsed = urlparse(self.path)
        base_url = f"http://{self.headers.get('Host', '127.0.0.1')}"
        if parsed.path in ("/", "/opds"):
            payload = render_feed(base_url, BOOKS[:4], page=1)
            self.send_bytes(payload, "application/atom+xml;profile=opds-catalog")
            return
        if parsed.path == "/opds/catalog":
            page = parse_qs(parsed.query).get("page", ["1"])[0]
            if page != "2":
                self.send_bytes(render_feed(base_url, BOOKS[:4], page=1), "application/atom+xml;profile=opds-catalog")
                return
            self.send_bytes(render_feed(base_url, BOOKS[4:], page=2), "application/atom+xml;profile=opds-catalog")
            return
        if parsed.path == "/opds/search":
            query = parse_qs(parsed.query).get("q", [""])[0].strip().lower()
            matches = tuple(
                book
                for book in BOOKS
                if not query
                or query in book["title"].lower()
                or query in book["summary"].lower()
            )
            self.send_bytes(render_feed(base_url, matches, page=2), "application/atom+xml;profile=opds-catalog")
            return
        if parsed.path.startswith("/books/"):
            filename = PurePosixPath(parsed.path).name
            payload = EPUBS.get(filename)
            if payload is None:
                self.send_error(HTTPStatus.NOT_FOUND, "Unknown test book")
                return
            self.send_bytes(payload, "application/epub+zip")
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def authorized(self) -> bool:
        username = self.server.username  # type: ignore[attr-defined]
        password = self.server.password  # type: ignore[attr-defined]
        if username is None:
            return True
        expected = "Basic " + base64.b64encode(f"{username}:{password}".encode()).decode()
        return self.headers.get("Authorization") == expected

    def send_bytes(self, payload: bytes, content_type: str) -> None:
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format: str, *args: object) -> None:
        print(f"[mock-opds] {self.address_string()} - {format % args}")


def local_addresses() -> list[str]:
    addresses = {"127.0.0.1"}
    try:
        _, _, resolved = socket.gethostbyname_ex(socket.gethostname())
        addresses.update(address for address in resolved if not address.startswith("127."))
    except OSError:
        pass
    return sorted(addresses)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a local OPDS test catalog for 开卷")
    parser.add_argument("--host", default="0.0.0.0", help="listen address, default: 0.0.0.0")
    parser.add_argument("--port", type=int, default=8765, help="listen port, default: 8765")
    parser.add_argument("--username", help="enable Basic Auth with this username")
    parser.add_argument("--password", help="Basic Auth password")
    args = parser.parse_args()
    if args.password is not None and args.username is None:
        parser.error("--password requires --username")

    server = ThreadingHTTPServer((args.host, args.port), MockOpdsHandler)
    server.username = args.username
    server.password = args.password or ""
    print("开卷本地 OPDS 测试服务已启动")
    for address in local_addresses():
        print(f"  OPDS 地址: http://{address}:{args.port}/opds")
    if args.username is not None:
        print(f"  Basic Auth: {args.username} / (已配置密码)")
    print("按 Ctrl-C 停止服务")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n正在停止 OPDS 测试服务")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
