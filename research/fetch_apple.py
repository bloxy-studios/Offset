#!/usr/bin/env python3
"""Fetch Apple developer doc JSON and flatten to readable text."""
import json, sys, urllib.request, re

BASE = "https://developer.apple.com/tutorials/data/documentation/"

def get(path):
    url = BASE + path.strip("/") + ".json"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

def flatten_inline(items):
    out = []
    for it in items or []:
        t = it.get("type")
        if t == "text":
            out.append(it.get("text", ""))
        elif t in ("codeVoice",):
            out.append("`" + it.get("code", "") + "`")
        elif t == "reference":
            out.append(it.get("identifier", "").split("/")[-1])
        elif t == "emphasis" or t == "strong":
            out.append(flatten_inline(it.get("inlineContent")))
        elif t == "inlineHead":
            out.append(flatten_inline(it.get("inlineContent")))
    return "".join(out)

def walk(content, depth=0):
    lines = []
    for block in content or []:
        t = block.get("type")
        if t == "paragraph":
            lines.append(flatten_inline(block.get("inlineContent")))
        elif t == "heading":
            lines.append("\n" + "#" * (block.get("level", 2)) + " " + block.get("text", ""))
        elif t == "codeListing":
            lines.append("```" + (block.get("syntax") or ""))
            lines.extend(block.get("code", []))
            lines.append("```")
        elif t == "unorderedList" or t == "orderedList":
            for item in block.get("items", []):
                sub = walk(item.get("content"), depth + 1)
                if sub:
                    lines.append("  " * depth + "- " + sub[0])
                    lines.extend("  " * depth + "  " + s for s in sub[1:])
        elif t == "aside":
            lines.append("[%s] " % block.get("name", "Note") + " ".join(walk(block.get("content"), depth)))
        elif t == "termList":
            for item in block.get("items", []):
                term = flatten_inline(item.get("term", {}).get("inlineContent"))
                defn = " ".join(walk(item.get("definition", {}).get("content"), depth))
                lines.append("- **%s**: %s" % (term, defn))
        elif t == "table":
            for row in block.get("rows", []):
                cells = [" ".join(walk(c, depth)) for c in row]
                lines.append("| " + " | ".join(cells) + " |")
    return lines

def dump(path):
    try:
        d = get(path)
    except Exception as e:
        print("FETCH-ERROR %s: %s" % (path, e))
        return
    md = d.get("metadata", {})
    print("=" * 80)
    print("PAGE:", md.get("title", path), "| roleHeading:", md.get("roleHeading", ""))
    plats = ["%s %s%s%s" % (p.get("name"), p.get("introducedAt", "?"),
             "+" , " (beta)" if p.get("beta") else "") for p in md.get("platforms", []) or []]
    print("AVAILABILITY:", "; ".join(plats) if plats else "n/a")
    print("URL: https://developer.apple.com" + d.get("identifier", {}).get("url", "").replace("doc://com.apple.documentation", "").replace("doc://com.apple.SwiftUI", "").replace("doc://com.apple.documentation/", "/"))
    # abstract
    abs_ = flatten_inline(d.get("abstract"))
    if abs_:
        print("ABSTRACT:", abs_)
    # declaration
    for sec in d.get("primaryContentSections", []) or []:
        k = sec.get("kind")
        if k == "declarations":
            for dec in sec.get("declarations", []):
                toks = "".join(t.get("text", "") for t in dec.get("tokens", []))
                print("DECLARATION:\n" + toks)
        elif k == "parameters":
            print("PARAMETERS:")
            for p in sec.get("parameters", []):
                print("  -", p.get("name"), ":", " ".join(walk(p.get("content"))))
        elif k == "content":
            print("DISCUSSION:")
            print("\n".join(walk(sec.get("content"))))
    # topic sections (list of symbols)
    ts = d.get("topicSections", []) or []
    if ts:
        print("TOPICS:")
        for s in ts:
            print("  ##", s.get("title", ""))
            for ident in s.get("identifiers", []):
                ref = d.get("references", {}).get(ident, {})
                frag = "".join(t.get("text", "") for t in ref.get("fragments", []) or [])
                print("    -", ref.get("title", ident.split("/")[-1]), "|", frag[:120])

if __name__ == "__main__":
    for p in sys.argv[1:]:
        dump(p)
