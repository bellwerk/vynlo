#!/usr/bin/env python3
from pathlib import Path
import sys

from validate_spec import check_markdown_links

root = Path(__file__).resolve().parents[1]
result = check_markdown_links(root)
for detail in result.details:
    print(detail)
print(f"markdown_file_links: {result.status}")
sys.exit(0 if result.status == "pass" else 1)
