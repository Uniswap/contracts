#!/usr/bin/env python3

"""
Regenerates deployment markdown files from existing JSON files using forge-chronicles.
Extracts chain IDs and explorer URLs from existing markdown files, then regenerates
them using the forge-chronicles library with the --skip-json flag.

Usage: python script/util/regenerate_deployment_markdown.py
"""

import os
import re
import sys
import subprocess
from pathlib import Path


def extract_explorer_url(content):
    """
    Extract explorer base URL from markdown content

    Args:
        content: Markdown file content

    Returns:
        Base explorer URL or None
    """
    # Look for anchor tags with href containing address links
    # Pattern: <a href="https://example.com/address/0x..." target="_blank">
    explorer_pattern = r'<a href="(https?://[^"/]+)'
    match = re.search(explorer_pattern, content)

    if match:
        return match.group(1)

    # Fallback: look for markdown links
    # Pattern: [0x...](https://example.com/address/0x...)
    markdown_pattern = r'\]\((https?://[^/\)]+)'
    md_match = re.search(markdown_pattern, content)

    if md_match:
        return md_match.group(1)

    return None


def regenerate_markdown(chain_id, explorer_url):
    """
    Regenerate markdown file for a chain using forge-chronicles

    Args:
        chain_id: Chain ID
        explorer_url: Block explorer base URL

    Returns:
        True if successful, False otherwise
    """
    cmd = [
        "node",
        "lib/forge-chronicles",
        "--skip-json",
        "--chain-id", str(chain_id),
        "--explorer-url", explorer_url
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"    ❌ Error: {e.stderr.strip()}")
        return False
    except Exception as e:
        print(f"    ❌ Unexpected error: {e}")
        return False


def extract_chain_explorers():
    """Extract chain IDs and explorer URLs from deployment markdown files"""
    # Get the deployments directory
    script_dir = Path(__file__).parent
    deployments_dir = script_dir.parent.parent / "deployments"

    results = []

    # Get all markdown files except index.md
    md_files = sorted(
        [f for f in deployments_dir.glob("*.md") if f.name != "index.md"],
        key=lambda x: int(x.stem)
    )

    print(f"Found {len(md_files)} deployment markdown files\n")
    print("=" * 80)
    print("PHASE 1: Extracting chain IDs and explorer URLs")
    print("=" * 80 + "\n")

    for md_file in md_files:
        chain_id = md_file.stem

        try:
            content = md_file.read_text(encoding="utf-8")
            explorer_url = extract_explorer_url(content)

            results.append({
                "chain_id": int(chain_id),
                "explorer_url": explorer_url or "not found"
            })

            status = explorer_url or "NOT FOUND"
            print(f"Chain ID: {chain_id:<10} | Explorer: {status}")

        except Exception as e:
            print(f"Error processing {md_file.name}: {e}")

    print(f"\n{'=' * 80}")
    print(f"Total chains processed: {len(results)}")
    print(f"Chains with explorers: {sum(1 for r in results if r['explorer_url'] != 'not found')}")

    missing_count = sum(1 for r in results if r['explorer_url'] == 'not found')
    print(f"Chains without explorers: {missing_count}")

    # Exit with error if any explorers are missing
    if missing_count > 0:
        print(f"\n❌ Error: {missing_count} chain(s) missing explorer URLs")
        sys.exit(1)

    return results


def main():
    """Main function to regenerate all deployment markdown files"""
    # Phase 1: Extract chain IDs and explorer URLs
    chains = extract_chain_explorers()

    # Phase 2: Regenerate markdown files
    print("\n" + "=" * 80)
    print("PHASE 2: Regenerating markdown files using forge-chronicles")
    print("=" * 80 + "\n")

    success_count = 0
    failed_chains = []

    for chain in chains:
        chain_id = chain["chain_id"]
        explorer_url = chain["explorer_url"]

        print(f"Regenerating chain {chain_id}...", end=" ")

        if regenerate_markdown(chain_id, explorer_url):
            print("✅")
            success_count += 1
        else:
            print("❌")
            failed_chains.append(chain_id)

    # Summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Total chains: {len(chains)}")
    print(f"Successfully regenerated: {success_count}")
    print(f"Failed: {len(failed_chains)}")

    if failed_chains:
        print(f"\nFailed chains: {', '.join(map(str, failed_chains))}")
        sys.exit(1)
    else:
        print("\n✅ All deployment markdown files regenerated successfully!")


if __name__ == "__main__":
    main()
