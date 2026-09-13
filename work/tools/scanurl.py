#!/usr/bin/env python3
"""Scan JS/JSON text for URLs, endpoints, and network API usage."""
import re, sys, os, collections, json

URL_RE = re.compile(rb"https?://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]{4,200}")
HOST_RE = re.compile(rb"\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:com|cn|net|org|io|com\.cn|net\.cn|org\.cn|top|xyz|vip|club|shop|tech|info|cc|co|me|tv|game)\b")

def scan(paths, label):
    urls = collections.Counter()
    hosts = collections.Counter()
    for p in paths:
        try:
            data = open(p, "rb").read()
        except Exception as e:
            continue
        for m in URL_RE.findall(data):
            urls[m.decode("utf8", "replace")] += 1
        for m in HOST_RE.findall(data):
            hosts[m.decode("utf8", "replace")] += 1
    print(f"===== {label}: {len(urls)} distinct URLs, {len(hosts)} hosts")
    print("--- hosts ---")
    for h, c in hosts.most_common(80):
        print(f"{c:6d}  {h}")
    print("--- urls (sample) ---")
    for u, c in urls.most_common(120):
        print(f"{c:6d}  {u}")

if __name__ == "__main__":
    files = []
    for root in sys.argv[1:]:
        if os.path.isdir(root):
            for dp, _, fns in os.walk(root):
                for fn in fns:
                    files.append(os.path.join(dp, fn))
        else:
            files.append(root)
    scan(files, " ".join(sys.argv[1:]))
