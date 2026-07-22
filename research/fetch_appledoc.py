#!/usr/bin/env python3
"""Fetch Apple doc JSON and extract title, declaration, availability, abstract, discussion, code listings."""
import json, sys, urllib.request, urllib.parse

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

def tokens_text(tokens):
    return "".join(t.get("text", "") for t in tokens)

def inline_text(items):
    out = []
    for i in items or []:
        t = i.get("type")
        if t == "text":
            out.append(i.get("text", ""))
        elif t == "codeVoice":
            out.append("`" + i.get("code", "") + "`")
        elif t == "reference":
            out.append(i.get("identifier", "").split("/")[-1])
        elif t == "emphasis" or t == "strong":
            out.append(inline_text(i.get("inlineContent", [])))
    return "".join(out)

def walk_content(content, out, depth=0):
    for c in content or []:
        t = c.get("type")
        if t == "paragraph":
            out.append(inline_text(c.get("inlineContent")))
        elif t == "codeListing":
            out.append("```swift\n" + "\n".join(c.get("code", [])) + "\n```")
        elif t == "heading":
            out.append("#" * (c.get("level", 3)) + " " + c.get("text", ""))
        elif t == "unorderedList" or t == "orderedList":
            for item in c.get("items", []):
                sub = []
                walk_content(item.get("content"), sub, depth + 1)
                out.append("- " + " ".join(sub))
        elif t == "aside":
            sub = []
            walk_content(c.get("content"), sub, depth + 1)
            out.append("> [%s] " % c.get("name", c.get("style", "note")) + " ".join(sub))
        elif t == "termList":
            for item in c.get("items", []):
                term = inline_text(item.get("term", {}).get("inlineContent"))
                sub = []
                walk_content(item.get("definition", {}).get("content"), sub, depth + 1)
                out.append("- **%s**: %s" % (term, " ".join(sub)))

def main(path):
    slug = urllib.parse.quote(path, safe="/():?_-.")
    url = "https://developer.apple.com/tutorials/data/documentation/%s.json" % slug
    try:
        d = get(url)
    except Exception as e:
        print("FETCH-ERROR %s -> %s" % (path, e))
        return
    md = d.get("metadata", {})
    print("=" * 80)
    print("PAGE:", md.get("title", "?"), "|", md.get("roleHeading", ""))
    print("URL: https://developer.apple.com/documentation/%s" % path)
    plats = md.get("platforms") or []
    av = ", ".join("%s %s%s%s" % (p.get("name"), p.get("introducedAt", "?"),
                                   " beta" if p.get("beta") else "",
                                   " DEPRECATED " + str(p.get("deprecatedAt")) if p.get("deprecatedAt") else "")
                   for p in plats)
    print("AVAILABILITY:", av or "(none listed)")
    for s in d.get("primaryContentSections", []):
        if s.get("kind") == "declarations":
            for dec in s.get("declarations", []):
                print("DECLARATION:")
                print(tokens_text(dec.get("tokens", [])))
    abstract = inline_text(d.get("abstract"))
    if abstract:
        print("ABSTRACT:", abstract)
    for s in d.get("primaryContentSections", []):
        k = s.get("kind")
        if k == "content":
            out = []
            walk_content(s.get("content"), out)
            print("DISCUSSION:")
            print("\n".join(out))
        elif k == "parameters":
            print("PARAMETERS:")
            for p in s.get("parameters", []):
                sub = []
                walk_content(p.get("content"), sub)
                print("- %s: %s" % (p.get("name"), " ".join(sub)))
    # topic sections: list child symbols
    ts = d.get("topicSections")
    if ts:
        print("TOPICS:")
        for sec in ts:
            ids = [i.split("/")[-1] for i in sec.get("identifiers", [])]
            print("- %s: %s" % (sec.get("title"), ", ".join(ids)))

if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
