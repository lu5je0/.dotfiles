#!/usr/bin/env python3
"""q-txt2kindle - 把中文 TXT 或 EPUB 转成 Kindle 电子书。

用法:
  q-txt2kindle *.txt                 # 转当前目录下的 TXT 小说
  q-txt2kindle novel.txt --dry-run   # 只看识别结果(编码/章节数/章节名)
  q-txt2kindle novel.txt -o out -f epub
  q-txt2kindle book.epub             # 保留原书结构并转成 MOBI
  q-txt2kindle . -j 4                # 并发转换目录中的 TXT 和 EPUB
"""

import argparse
import bisect
import collections
import concurrent.futures as cf
import hashlib
import html
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import zipfile

CN_DIGITS = {'零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5,
             '六': 6, '七': 7, '八': 8, '九': 9}
CN_UNITS = {'十': 10, '百': 100, '千': 1000, '万': 10000}
CIRCLED = {chr(0x2460 + k): str(k + 1) for k in range(9)}        # ①..⑨
CIRCLED['\u2469'] = '10'                                         # ⑩

COMMON_HANZI = set('的一是了不我在人有他这上们到说和地也子时道你就那要会着没看好自来'
                   '过里下大而生去能对小多然于心学么之都得实可以为把很如从')

NOISE_RE = re.compile(r'^\s*(?:章节编号|点阅|點閱|字数|字數|来源地址|來源地址|本章字数)\s*[:：]'
                      r'|^\s*https?://\S+\s*$')

IDEO_SPACE = '\u3000'


# ---------------------------------------------------------------- 编码处理
def decode_bytes(raw, forced=None):
    """返回 (text, encoding)。自动识别 utf-8 / gb18030 / big5 / utf-16。"""
    if forced:
        return raw.decode(forced, errors='replace'), forced
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        return raw.decode('utf-16', errors='replace'), 'utf-16'
    candidates = []
    for enc in ('utf-8-sig', 'gb18030', 'big5hkscs', 'shift_jis'):
        try:
            text = raw.decode(enc)
        except UnicodeDecodeError:
            continue
        candidates.append((score_chinese(text), enc, text))
    if not candidates:
        return raw.decode('gb18030', errors='replace'), 'gb18030(replace)'
    candidates.sort(key=lambda x: -x[0])
    score, enc, text = candidates[0]
    return text, enc


def score_chinese(text):
    sample = text[:200000]
    cjk = [c for c in sample if '\u4e00' <= c <= '\u9fff']
    if not cjk:
        return 0.0
    hit = sum(1 for c in cjk if c in COMMON_HANZI)
    return hit / len(cjk) + len(cjk) / max(len(sample), 1) * 0.1


# ---------------------------------------------------------------- 数字解析
def cn2num(s):
    s = s.strip()
    if not s:
        return None
    if any(c in CIRCLED for c in s):
        # 圈数字按十进制位拼: "①⑤" = 15。这些源文件没有 ⓪，多位数里拿 ⑩ 占 0 位
        digits = [CIRCLED.get(c, c) for c in s]
        if len(digits) > 1:
            digits = ['0' if d == '10' else d for d in digits]
        s = ''.join(digits)
    if s.isdigit():
        try:
            return int(s)
        except ValueError:
            return None
    total, section, number = 0, 0, 0
    for ch in s:
        if ch in CN_DIGITS:
            number = CN_DIGITS[ch]
        elif ch in CN_UNITS:
            unit = CN_UNITS[ch]
            if unit == 10000:
                section = (section + number) * unit
                total += section
                section = number = 0
            else:
                if number == 0:
                    number = 1
                section += number * unit
                number = 0
        else:
            return None
    return total + section + number


# ---------------------------------------------------------------- 章节识别
STRONG_PATTERNS = [
    re.compile(r'^(?:\d{1,4}[\s.、]+)?第\s*([0-9〇零一二三四五六七八九十百千两\u2460-\u2469]{1,8})'
               r'\s*[章回卷話话節节篇折][\s:：、.]*(.*)$'),
    re.compile(r'^(?:Chapter|CHAPTER|chapter)\s*(\d{1,4})[\s.:：-]*(.*)$'),
]
UNNUMBERED_RE = re.compile(r'^(番外|外篇|序章|序言|楔子|引子|尾声|尾聲|终章|終章|后记|後記|'
                           r'结局|結局|全文完|作者的话)(.{0,16})$')
# 正文句子里也可能出现“第三回”这类字样，这类行多半带句号或多个逗号，据此排除
SENTENCE_RE = re.compile(r'。|，[^，]*，')
WEAK_PATTERNS = [
    re.compile(r'^(\d{1,4})\s*[.、．]\s*(\S.*)$'),
    re.compile(r'^(\d{1,4})\s*[:：]\s*(\S.*)$'),
    re.compile(r'^(\d{1,4})[ \t]+(\S.*)$'),
    re.compile(r'^(\d{1,4})$'),
    re.compile(r'^(\d{1,4})(\S.*)$'),
]

STRONG_W, WEAK_W = 10, 1


def norm_line(raw):
    line = raw.replace('\t', ' ').replace('\u00a0', ' ')
    # 剔除控制类字符；emoji 等非 BMP 字符 MOBI6 无法渲染，会让 Kindle 打开时卡死
    line = ''.join(c for c in line
                   if unicodedata.category(c)[0] != 'C' and ord(c) <= 0xffff)
    return line.strip().strip(IDEO_SPACE).strip()


SEP_CHARS = '、,，.．·:：'


def split_marker(line):
    """把 "☆、第1章" 拆成 ("☆、", "第1章")；没有装饰前缀时返回 None。

    晋江等站点导出的标题带 "☆、" 这类前缀，符号后往往还跟着顿号一类分隔符。
    """
    i = 0
    while i < len(line) and unicodedata.category(line[i]) in ('So', 'Sk', 'Sm', 'Sc'):
        i += 1
    if not i:
        return None
    j = i
    while j < len(line) and (line[j].isspace() or line[j] in SEP_CHARS):
        j += 1
    rest = line[j:].strip()
    if not rest:
        return None                          # 纯符号的分隔线
    return line[:j].strip(), rest


def strip_deco(line):
    m = split_marker(line)
    return m[1] if m else line


def indented(raw):
    """正文缩进行(全角空格开头或多个空格开头)不当作标题。"""
    return raw.startswith(IDEO_SPACE) or re.match(r'^[ \t]{2,}\S', raw) is not None


def collect_candidates(lines, patterns, weight, max_len, strict_indent, reject_prose=False):
    out = []
    for i, raw in enumerate(lines):
        if strict_indent and indented(raw):
            continue
        m = split_marker(norm_line(raw))
        pre, line = m if m else ('', norm_line(raw))
        if not line or len(line) > max_len:
            continue
        if reject_prose and SENTENCE_RE.search(line):
            continue
        for pat in patterns:
            m = pat.match(line)
            if not m:
                continue
            num = cn2num(m.group(1))
            if num is None or num > 9999:
                break
            out.append({'pos': i, 'num': num, 'text': line, 'w': weight, 'pre': pre})
            break
    return out


HEADER_RE = re.compile(r'^(?:文案|标签|內容标签|内容标签|一句话简介|立意|主角|配角|其它|其他'
                       r'|视角|评分|收藏|字数|字數|文章类型|作品风格|风格|系列|所属系列'
                       r'|霸王票排行|霸王票|灌溉|营养液|搜索关键字|进度|完结时间)\s*[:：]')


def title_like(text):
    """句子、"文〃√" 这类竖排水印、站点页首字段都不是标题。"""
    if SENTENCE_RE.search(text) or HEADER_RE.match(text):
        return False
    sym = sum(1 for c in text if unicodedata.category(c) in ('So', 'Sk', 'Sm'))
    return sym <= 0.2 * len(text)


def marker_lines(lines, max_len):
    """枚举带装饰前缀的行: [(行号, 前缀, 去掉前缀的正文)]。"""
    out = []
    for i, raw in enumerate(lines):
        m = split_marker(norm_line(raw))
        if m and len(m[1]) <= max_len and title_like(m[1]):
            out.append((i, m[0], m[1]))
    return out


def series_of(marks):
    """已确认章节里出现 5 次以上的装饰前缀，视为一个章节系列。"""
    seen = collections.Counter(m['pre'] for m in marks if m['pre'])
    return {p for p, n in seen.items() if n >= 5}


def extend_series(marks, lines, max_len):
    """把已确认系列下漏掉的行补成章节。

    "☆、美人" 这类标题没有编号，单看一行没法判断；但同一前缀下已经有 5 个
    章节被编号确认过，剩下同样写法的行就是同系列的章节。
    """
    known = {m['pos'] for m in marks}
    series = series_of(marks)
    return [{'pos': i, 'num': 0, 'text': t, 'w': STRONG_W, 'pre': pre}
            for i, pre, t in marker_lines(lines, max_len)
            if pre in series and i not in known]


class FenwickMax:
    def __init__(self, n):
        self.n = n
        self.t = [(0, -1)] * (n + 1)

    def update(self, i, val):
        i += 1
        while i <= self.n:
            if val > self.t[i]:
                self.t[i] = val
            i += i & -i

    def query(self, i):
        """前缀 [0, i] 最大值"""
        i += 1
        best = (0, -1)
        while i > 0:
            if self.t[i] > best:
                best = self.t[i]
            i -= i & -i
        return best


def best_chain(items):
    """加权最长递增子序列: 在候选标题里挑出编号单调递增、权重和最大的一条链。"""
    if not items:
        return []
    n = len(items)
    parent = [-1] * n
    best_score = [0] * n
    fen = FenwickMax(10002)
    order = sorted(range(n), key=lambda k: items[k]['pos'])
    for idx in order:
        num = items[idx]['num']
        prev_score, prev_idx = fen.query(num - 1) if num > 0 else (0, -1)
        best_score[idx] = prev_score + items[idx]['w']
        parent[idx] = prev_idx
        fen.update(num, (best_score[idx], idx))
    end = max(range(n), key=lambda k: (best_score[k], -items[k]['pos']))
    chain, cur = [], end
    while cur != -1:
        chain.append(items[cur])
        cur = parent[cur]
    chain.reverse()
    return chain


def pick_weak(lines, max_len, strict):
    """合并所有质量达标的弱模式候选，再用递增链筛掉广告行等杂质。

    有的文件前后换过章节写法(前 23 章 "1.标题"，之后 "24 标题")，所以不能只选一种。
    """
    sets = [collect_candidates(lines, [p], WEAK_W, max_len, strict) for p in WEAK_PATTERNS]
    chains = [best_chain(c) for c in sets]
    scores = [len(ch) if len(ch) >= 5 and len(ch) >= 0.5 * len(c) else 0
              for ch, c in zip(chains, sets)]
    top = max(scores) if scores else 0
    if not top:
        return []
    merged, seen = [], set()
    for score, chain in zip(scores, chains):
        if score < max(5, 0.1 * top):
            continue
        for item in chain:
            if item['pos'] not in seen:
                seen.add(item['pos'])
                merged.append(item)
    return best_chain(merged)


def keep_between_anchors(weak, anchors):
    """弱标题必须落在前后两个强锚点的编号区间内，否则视为正文里的数字。"""
    if not anchors:
        return weak
    apos = [a['pos'] for a in anchors]
    kept = []
    for w in weak:
        j = bisect.bisect_left(apos, w['pos'])
        lo = anchors[j - 1]['num'] if j > 0 else 0
        hi = anchors[j]['num'] if j < len(anchors) else 10000
        if lo < hi and not (lo < w['num'] < hi):
            continue  # 前后锚点自身递增时才做这个判断
        kept.append(w)
    return kept


def detect_chapters(lines, max_len=48, extra_pattern=None):
    """返回 [(行号, 标题)]，已按位置排序。"""
    chain = []
    for strict in (True, False):
        # 强模式("第几章")辨识度高，全部采信；很多源文件章号本身重复/跳号，
        # 若强行要求全局递增反而会把正章丢掉
        strong = collect_candidates(lines, STRONG_PATTERNS, STRONG_W, max_len + 20, strict,
                                    reject_prose=True)
        weak = keep_between_anchors(pick_weak(lines, max_len, strict), strong)
        chain = sorted(strong + weak, key=lambda c: c['pos'])
        if len(chain) >= 3:
            break

    chain += extend_series(chain, lines, max_len)
    chain.sort(key=lambda c: c['pos'])

    if extra_pattern:
        pat = re.compile(extra_pattern)
        seen = {c['pos'] for c in chain}
        for i, raw in enumerate(lines):
            line = norm_line(raw)
            if i not in seen and line and pat.match(line):
                chain.append({'pos': i, 'num': 0, 'text': line, 'w': STRONG_W})

    # 番外/序章 等没有编号的章节单独补进来
    known = {c['pos'] for c in chain}
    for i, raw in enumerate(lines):
        if i in known or indented(raw):
            continue
        line = strip_deco(norm_line(raw))
        if line and len(line) <= max_len and UNNUMBERED_RE.match(line):
            chain.append({'pos': i, 'num': 0, 'text': line, 'w': STRONG_W})

    chain.sort(key=lambda c: c['pos'])

    # 去掉紧邻的重复标题(有些站点会把标题输出两遍，两遍写法还可能不一致)
    result, last, prev = [], {}, None
    for c in chain:
        key = re.sub(r'\s+', '', c['text'])
        if key in last and c['pos'] - last[key] <= 40:
            last[key] = c['pos']
            continue
        if prev and c['pos'] - prev[1] <= 40 and (key in prev[0] or prev[0] in key):
            last[key] = c['pos']
            if len(key) < len(prev[0]):      # 后一行更干净，标题用它，位置仍取前一处
                result[-1] = (result[-1][0], c['text'])
                prev = (key, prev[1])
            continue
        last[key] = c['pos']
        prev = (key, c['pos'])
        result.append((c['pos'], c['text']))
    return result


# ---------------------------------------------------------------- 元数据
def guess_meta(lines, path):
    title = author = None
    for raw in lines[:120]:
        line = norm_line(raw)
        m = re.match(r'^(?:书名|書名|名称|名稱|本书名称)\s*[:：]\s*(\S.*)$', line)
        if m and not title:
            title = m.group(1).strip()
        m = re.match(r'^(?:作者|作家|本书作者)\s*[:：]\s*(\S.*)$', line)
        if m and not author:
            author = m.group(1).strip()
    stem = os.path.splitext(os.path.basename(path))[0]
    if not title:
        m = re.search(r'[《【]([^》】]{2,40})[》】]', stem)
        title = m.group(1) if m else re.sub(r'[_\s]+', ' ', stem)[:60]
    if not author:
        m = re.search(r'(?:作者|作家)\s*[:：]?\s*([^_（(【\s]{1,20})', stem)
        author = m.group(1) if m else '未知'
    title = re.sub(r'^[\[【（(][^\]】）)]{0,20}[\]】）)]\s*', '', title)
    title = re.split(r'\s*(?:作者|作家)\s*[:：]', title)[0]
    title = title.strip(' _-~《》【】')
    return re.sub(r'\s+', ' ', title).strip(), re.sub(r'\s+', ' ', author).strip()


# ---------------------------------------------------------------- EPUB 输出
CSS = """body { font-family: serif; line-height: 1.6; margin: 0 6%; }
h1.ct { font-size: 1.2em; margin: 1.2em 0 1em; text-align: center;
        page-break-before: always; }
p { text-indent: 2em; margin: 0.35em 0; }
p.sep { text-indent: 0; text-align: center; }
"""

CHAP_TMPL = """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh"><head>
<meta charset="utf-8"/><title>{title}</title>
<link rel="stylesheet" type="text/css" href="../style.css"/>
</head><body>
<h1 class="ct">{title}</h1>
{body}
</body></html>
"""

MAX_CHARS = 260000  # 单个 xhtml 过大时切片，避免 Kindle 渲染卡顿


def build_body(body_lines, keep_noise):
    parts = []
    for raw in body_lines:
        line = norm_line(raw)
        if not line:
            continue
        if not keep_noise and NOISE_RE.match(line):
            continue
        cls = ' class="sep"' if re.fullmatch(r'[-—=＝*※~·\s]{3,}', line) else ''
        parts.append('<p%s>%s</p>' % (cls, html.escape(line)))
    return parts


def write_epub(out_path, title, author, chapters, keep_noise):
    """chapters: [(标题, [正文行])]"""
    docs = []  # (filename, title, xhtml, in_toc)
    for idx, (ctitle, body_lines) in enumerate(chapters, 1):
        paras = build_body(body_lines, keep_noise) or ['<p></p>']
        chunks, cur, size = [], [], 0
        for p in paras:
            if size + len(p) > MAX_CHARS and cur:
                chunks.append(cur)
                cur, size = [], 0
            cur.append(p)
            size += len(p)
        chunks.append(cur)
        for part, chunk in enumerate(chunks, 1):
            name = 'text/c%04d_%d.xhtml' % (idx, part)
            shown = ctitle if part == 1 else '%s (%d)' % (ctitle, part)
            xhtml = CHAP_TMPL.format(title=html.escape(shown), body='\n'.join(chunk))
            docs.append((name, shown, xhtml, part == 1))

    uid = 'urn:uuid:' + hashlib.md5((title + author).encode()).hexdigest()
    manifest, spine, navlis, navpoints = [], [], [], []
    for i, (name, shown, _x, in_toc) in enumerate(docs, 1):
        manifest.append('<item id="d%d" href="%s" media-type="application/xhtml+xml"/>'
                        % (i, name))
        spine.append('<itemref idref="d%d"/>' % i)
        if in_toc:
            navlis.append('<li><a href="%s">%s</a></li>' % (name, html.escape(shown)))
            navpoints.append(
                '<navPoint id="n%d" playOrder="%d"><navLabel><text>%s</text></navLabel>'
                '<content src="%s"/></navPoint>' % (i, len(navpoints) + 1,
                                                    html.escape(shown), name))

    opf = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bid">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="bid">%s</dc:identifier>
<dc:title>%s</dc:title>
<dc:creator>%s</dc:creator>
<dc:language>zh-CN</dc:language>
<meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="css" href="style.css" media-type="text/css"/>
%s
</manifest>
<spine toc="ncx">
<itemref idref="nav" linear="no"/>
%s
</spine>
<guide><reference type="toc" title="目录" href="nav.xhtml"/></guide>
</package>
""" % (uid, html.escape(title), html.escape(author),
       '\n'.join(manifest), '\n'.join(spine))

    nav = """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"
      xml:lang="zh"><head><meta charset="utf-8"/><title>目录</title></head><body>
<nav epub:type="toc" id="toc"><h1>目录</h1><ol>
%s
</ol></nav></body></html>
""" % '\n'.join(navlis)

    ncx = """<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="%s"/></head>
<docTitle><text>%s</text></docTitle>
<navMap>
%s
</navMap></ncx>
""" % (uid, html.escape(title), '\n'.join(navpoints))

    with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip',
                   compress_type=zipfile.ZIP_STORED)
        z.writestr('META-INF/container.xml',
                   '<?xml version="1.0"?>\n<container version="1.0" '
                   'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                   '<rootfiles><rootfile full-path="OEBPS/content.opf" '
                   'media-type="application/oebps-package+xml"/></rootfiles></container>')
        z.writestr('OEBPS/content.opf', opf)
        z.writestr('OEBPS/nav.xhtml', nav)
        z.writestr('OEBPS/toc.ncx', ncx)
        z.writestr('OEBPS/style.css', CSS)
        for name, _s, xhtml, _t in docs:
            z.writestr('OEBPS/' + name, xhtml)
    return sum(1 for d in docs if d[3])


# ---------------------------------------------------------------- 单文件流程
def drop_repeated_title(title, body):
    """章首若重复出现标题(部分站点会输出两遍)，去掉它。"""
    key = re.sub(r'\s+', '', title)
    out, checked = [], 0
    for raw in body:
        line = norm_line(raw)
        if checked < 6 and line:
            checked += 1
            if re.sub(r'\s+', '', line) == key:
                continue
        out.append(raw)
    return out


def split_chapters(lines, marks):
    chapters = []
    if not marks:
        return [('全文', lines)]
    first = marks[0][0]
    if len([l for l in lines[:first] if norm_line(l)]) >= 3:
        chapters.append(('内容简介', lines[:first]))
    for i, (pos, title) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(lines)
        chapters.append((title, drop_repeated_title(title, lines[pos + 1:end])))
    return chapters


def to_mobi(epub_path, target, huffdic=False):
    """epub -> mobi。返回 kindlegen 的输出；成败由调用方看产物是否存在。

    kindlegen 有警告时退出码也是 1，不能拿它判断成败。
    在网络文件系统(CIFS 等)上 kindlegen 无法正确合并 KF8，因此统一在本地
    临时目录执行，完成后再移动产物到目标路径。
    """
    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_epub = os.path.join(tmpdir, 'book.epub')
        tmp_mobi = os.path.join(tmpdir, 'book.mobi')
        shutil.copy2(epub_path, tmp_epub)
        r = subprocess.run([shutil.which('kindlegen'), tmp_epub,
                            '-c2' if huffdic else '-c1',
                            '-dont_append_source', '-o', 'book.mobi'],
                           capture_output=True, text=True)
        if os.path.exists(tmp_mobi):
            shutil.move(tmp_mobi, target)
    return r.stdout + r.stderr


def convert_txt(path, args):
    """返回 (outputs, log)；并发下由调用方整块打印 log，避免多文件输出穿插。"""
    log = []
    with open(path, 'rb') as f:
        raw = f.read()
    text, enc = decode_bytes(raw, args.encoding)
    lines = text.replace('\r\n', '\n').replace('\r', '\n').split('\n')
    title, author = guess_meta(lines, path)
    title = args.title or title
    author = args.author or author
    marks = detect_chapters(lines, args.max_title_len, args.pattern)

    log.append('\x1b[1m%s\x1b[0m' % os.path.basename(path))
    log.append('  编码: %s%s' % (enc, '' if enc.startswith('utf-8') else '  -> 转 UTF-8'))
    log.append('  书名: %s   作者: %s' % (title, author))
    dropped = sum(1 for c in text if ord(c) > 0xffff)
    if dropped:
        log.append('  \x1b[33m剔除 %d 个非 BMP 字符(emoji 等，MOBI6 渲染器会卡死)\x1b[0m' % dropped)
    log.append('  章节: %d' % len(marks))
    if marks:
        show = marks if args.list_chapters or len(marks) <= 6 else \
            marks[:3] + [('...', '...')] + marks[-3:]
        for pos, t in show:
            log.append('    %s' % (t if pos == '...' else '%-8s %s' % ('L%d' % pos, t)))
    else:
        log.append('    \x1b[33m未识别到章节，整本作为一章(可用 --pattern 指定)\x1b[0m')
    if args.dry_run:
        return [], log

    chapters = split_chapters(lines, marks)
    stem = re.sub(r'[/\\:]', '_', title) or 'book'
    epub_path = os.path.join(args.outdir, stem + '.epub')
    n_toc = write_epub(epub_path, title, author, chapters, args.keep_noise)
    outputs = []

    def report(target):
        log.append('  \x1b[32m已生成\x1b[0m %s  (目录 %d 项, %.1f MB)'
                   % (target, n_toc, os.path.getsize(target) / 1048576))
        outputs.append(target)

    if args.format in ('epub', 'both'):
        report(epub_path)
    if args.format in ('mobi', 'both'):
        target = os.path.join(args.outdir, stem + '.mobi')
        out = to_mobi(epub_path, target, args.c2)
        if os.path.exists(target):
            report(target)
        else:
            log.append('  \x1b[31mkindlegen 失败\x1b[0m\n%s' % out.strip()[-500:])
    if args.format not in ('epub', 'both'):
        os.remove(epub_path)                     # EPUB 只是中间产物
    return outputs, log


def convert_epub(path, args):
    log = ['\x1b[1m%s\x1b[0m' % os.path.basename(path),
           '  来源: EPUB（保留原书结构）']
    if args.dry_run:
        return [], log

    stem = os.path.splitext(os.path.basename(path))[0]
    target = os.path.join(args.outdir, stem + '.mobi')
    out = to_mobi(path, target, args.c2)
    if os.path.exists(target):
        log.append('  \x1b[32m已生成\x1b[0m %s  (%.1f MB)'
                   % (target, os.path.getsize(target) / 1048576))
        return [target], log

    log.append('  \x1b[31mkindlegen 失败\x1b[0m\n%s' % out.strip()[-500:])
    return [], log


def convert(path, args):
    if path.lower().endswith('.epub'):
        return convert_epub(path, args)
    return convert_txt(path, args)


def main():
    ap = argparse.ArgumentParser(
        prog='q-txt2kindle',
        description='中文 TXT 或 EPUB -> Kindle 电子书（TXT 自动识别编码与章节）')
    ap.add_argument('inputs', nargs='+', help='TXT、EPUB 文件或目录')
    ap.add_argument('-o', '--outdir', default='kindle', help='输出目录(默认 ./kindle)')
    ap.add_argument('-f', '--format', default='mobi',
                    choices=['mobi', 'epub', 'both'],
                    help='输出格式（EPUB 输入仅支持 mobi；TXT 默认 mobi）')
    ap.add_argument('-n', '--dry-run', action='store_true', help='只识别不生成')
    ap.add_argument('-l', '--list-chapters', action='store_true', help='列出全部章节名')
    ap.add_argument('--encoding', help='强制指定源编码，如 gb18030')
    ap.add_argument('--pattern', help='附加章节标题正则')
    ap.add_argument('--title')
    ap.add_argument('--author')
    ap.add_argument('--max-title-len', type=int, default=48, help='标题最大长度(默认48)')
    ap.add_argument('--keep-noise', action='store_true', help='保留 章节编号/点阅 等噪音行')
    ap.add_argument('--c2', action='store_true',
                    help='kindlegen 用 huffdic 压缩(体积约小 4 倍，但慢一个数量级)')
    ap.add_argument('-j', '--jobs', type=int, default=0,
                    help='并发转换的文件数(默认 CPU 核数；1 为串行)')
    args = ap.parse_args()

    files = []
    for item in args.inputs:
        if os.path.isdir(item):
            files += sorted(os.path.join(item, f) for f in os.listdir(item)
                            if f.lower().endswith(('.txt', '.epub')))
        elif item.lower().endswith(('.txt', '.epub')):
            files.append(item)
        else:
            print('跳过非 TXT/EPUB: %s' % item, file=sys.stderr)
    if not files:
        sys.exit('没有找到 TXT 或 EPUB 文件')
    if any(path.lower().endswith('.epub') for path in files) and args.format != 'mobi':
        sys.exit('EPUB 输入仅支持 -f mobi')
    if args.format != 'epub' and not args.dry_run and not shutil.which('kindlegen'):
        sys.exit('mobi 需要 kindlegen：yay -S kindlegen\n'
                 '(TXT 只要 epub 可以加 -f epub，无外部依赖)')
    if not args.dry_run:
        os.makedirs(args.outdir, exist_ok=True)

    jobs = args.jobs if args.jobs > 0 else (os.cpu_count() or 1)
    jobs = max(1, min(jobs, len(files)))

    ok = 0
    ex = cf.ThreadPoolExecutor(max_workers=jobs)
    futures = {ex.submit(convert, path, args): path for path in files}
    try:
        for fut in cf.as_completed(futures):
            path = futures[fut]
            try:
                _outputs, log = fut.result()
            except Exception as e:  # noqa: BLE001
                print('  \x1b[31m失败\x1b[0m %s: %s' % (path, e), file=sys.stderr)
                continue
            print('\n' + '\n'.join(log))
            ok += 1
    except KeyboardInterrupt:
        ex.shutdown(wait=False, cancel_futures=True)
        print('\n\x1b[33m已取消\x1b[0m (已完成 %d/%d)' % (ok, len(files)), file=sys.stderr)
        # 正在跑的 kindlegen 已随 SIGINT 一起收到信号；用 _exit 跳过
        # 解释器退出时对工作线程的 join，否则会再抛一次 KeyboardInterrupt
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(130)
    ex.shutdown()
    print('\n完成 %d/%d' % (ok, len(files)))


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
