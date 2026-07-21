#!/usr/bin/env python3
"""
tools/build_catalog.py

Aggregates KOReader plugins and user patches from GitHub into a single catalog.json.
Can be run locally or in GitHub Actions.
Uses GITHUB_TOKEN environment variable if available for high rate-limits.
"""

import os
import sys
import json
import time
import urllib.request
import urllib.parse
from datetime import datetime, timezone

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
BASE_URL = "https://api.github.com"
USER_AGENT = "KOReader-Storefront-CatalogBuilder/1.0"

PLUGIN_QUERIES = [
    "topic:koreader-plugin",
    'in:name ".koplugin"',
]

PATCH_QUERIES = [
    "topic:koreader-user-patch",
    'in:name "KOReader.patches"',
    'in:name "koreader-patches"',
    'in:name "koreader-user-patches"',
]

def make_request(url):
    req = urllib.request.Request(url)
    req.add_header("User-Agent", USER_AGENT)
    req.add_header("Accept", "application/vnd.github+json")
    if GITHUB_TOKEN and len(GITHUB_TOKEN.strip()) > 0:
        req.add_header("Authorization", f"Bearer {GITHUB_TOKEN.strip()}")
    
    try:
        with urllib.request.urlopen(req) as resp:
            data = resp.read().decode("utf-8")
            return json.loads(data)
    except urllib.error.HTTPError as e:
        if e.code == 401 and GITHUB_TOKEN:
            # Token might be invalid locally; retry once without token
            req2 = urllib.request.Request(url)
            req2.add_header("User-Agent", USER_AGENT)
            req2.add_header("Accept", "application/vnd.github+json")
            try:
                with urllib.request.urlopen(req2) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except Exception:
                return None
        if e.code != 404: # 404 is expected for repos without releases
            print(f"HTTP Error {e.code} for {url}: {e.reason}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Request error for {url}: {e}", file=sys.stderr)
        return None

def search_repositories(base_query):
    all_items = []
    # GitHub search excludes forks by default unless fork:only is specified.
    # Search both non-fork and fork repositories.
    sub_queries = [
        base_query,
        base_query + " fork:only",
    ]
    
    for q in sub_queries:
        page = 1
        per_page = 100
        while page <= 10:  # GitHub API limit: 1,000 max results per query (10 pages of 100)
            encoded_q = urllib.parse.quote(q)
            url = f"{BASE_URL}/search/repositories?q={encoded_q}&sort=stars&order=desc&per_page={per_page}&page={page}"
            print(f"Searching GitHub (page {page}): {q}")
            res = make_request(url)
            if not res or "items" not in res:
                break
            items = res.get("items", [])
            if not items:
                break
            all_items.extend(items)
            if len(items) < per_page:
                break
            page += 1
            time.sleep(0.1)
            
    return all_items

def get_latest_release(owner, repo):
    url = f"{BASE_URL}/repos/{owner}/{repo}/releases/latest"
    return make_request(url)

def fetch_patch_files(owner, repo, default_branch="HEAD"):
    url = f"{BASE_URL}/repos/{owner}/{repo}/git/trees/{default_branch}?recursive=1"
    res = make_request(url)
    if not res or "tree" not in res:
        return []
    
    patch_files = []
    for item in res["tree"]:
        path = item.get("path", "")
        if item.get("type") == "blob" and (path.endswith(".lua") or path.endswith(".lua.disabled")):
            filename = os.path.basename(path)
            patch_files.append({
                "path": path,
                "filename": filename,
                "sha": item.get("sha", ""),
                "size": item.get("size", 0),
                "download_url": f"https://raw.githubusercontent.com/{owner}/{repo}/{default_branch}/{path}",
                "branch": default_branch,
            })
    return patch_files

def process_repos(queries, is_patch=False):
    repo_map = {}
    for q in queries:
        items = search_repositories(q)
        for item in items:
            repo_id = item.get("id")
            if repo_id and repo_id not in repo_map:
                repo_map[repo_id] = item
    
    processed = []
    for repo_id, repo in repo_map.items():
        owner = repo.get("owner", {}).get("login", "")
        repo_name = repo.get("name", "")
        full_name = repo.get("full_name", f"{owner}/{repo_name}")
        default_branch = repo.get("default_branch", "main")
        
        print(f"Processing repo: {full_name}")
        
        # Prepare normalized record
        record = {
            "id": repo_id,
            "repo_id": repo_id,
            "name": repo_name,
            "owner": owner,
            "full_name": full_name,
            "description": repo.get("description") or "",
            "stars": repo.get("stargazers_count", 0),
            "stargazers_count": repo.get("stargazers_count", 0),
            "fork": repo.get("fork", False),
            "language": repo.get("language") or "",
            "homepage": repo.get("homepage") or "",
            "default_branch": default_branch,
            "pushed_at": repo.get("pushed_at") or "",
            "updated_at": repo.get("updated_at") or "",
            "html_url": repo.get("html_url") or f"https://github.com/{full_name}",
        }
        
        # Check latest release
        rel = get_latest_release(owner, repo_name)
        if rel and type(rel) == dict and "tag_name" in rel:
            tag_name = rel.get("tag_name", "")
            assets = rel.get("assets", [])
            download_url = None
            for asset in assets:
                asset_name = asset.get("name", "")
                if asset_name.endswith(".zip"):
                    download_url = asset.get("browser_download_url")
                    break
            if not download_url and "zipball_url" in rel:
                download_url = rel.get("zipball_url")
                
            record["latest_release"] = {
                "tag_name": tag_name,
                "published_at": rel.get("published_at") or "",
                "download_url": download_url,
                "name": rel.get("name") or "",
            }
        
        if is_patch:
            print(f"Fetching patch tree for {full_name}...")
            patch_files = fetch_patch_files(owner, repo_name, default_branch)
            record["patch_files"] = patch_files
            
        processed.append(record)
        time.sleep(0.2) # Friendly rate spacing
        
    return processed

def main():
    print("=== KOReader Storefront Catalog Builder ===")
    start_time = time.time()
    
    plugins = process_repos(PLUGIN_QUERIES, is_patch=False)
    patches = process_repos(PATCH_QUERIES, is_patch=True)
    
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    catalog = {
        "version": 1,
        "generated_at": now_iso,
        "generated_timestamp": int(time.time()),
        "stats": {
            "total_plugins": len(plugins),
            "total_patches": len(patches),
        },
        "plugins": plugins,
        "patches": patches,
    }
    
    script_dir = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
    output_path = os.path.abspath(os.path.join(script_dir, "..", "catalog.json"))
    
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
        
    elapsed = time.time() - start_time
    print(f"Successfully generated catalog.json at {output_path} in {elapsed:.2f}s")
    print(f"Plugins: {len(plugins)}, Patches: {len(patches)}")

if __name__ == "__main__":
    main()
