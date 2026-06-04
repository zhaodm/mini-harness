#!/usr/bin/env python3
"""批量修复 PPT slides 字号 — 将小字号按映射表上调至可读范围

用法: python3 scripts/fix-ppt-fonts.py <目录路径>
示例: python3 scripts/fix-ppt-fonts.py deliverables/REQ001/output
"""
import re, os, sys

# 字号映射表：原始小字号 → 修复后字号
FONT_MAP = {
    11: 18, 12: 20, 13: 20, 14: 22, 15: 24, 16: 24,
    17: 26, 18: 28, 20: 30, 22: 32, 24: 34,
}

def scale_font(match):
    size = int(match.group(1))
    new_size = FONT_MAP.get(size, size)
    return f"font-size: {new_size}px"

def process_file(path):
    content = open(path, encoding='utf-8').read()
    new_content = re.sub(r'font-size:\s*(\d+)px', scale_font, content)
    if new_content != content:
        open(path, 'w', encoding='utf-8').write(new_content)
        return True
    return False

def main():
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."

    if not os.path.isdir(target_dir):
        print(f"ERROR: 目录不存在: {target_dir}")
        sys.exit(1)

    fixed = 0
    skipped = 0

    for f in sorted(os.listdir(target_dir)):
        if not f.endswith('.html'):
            continue
        path = os.path.join(target_dir, f)
        if process_file(path):
            print(f"✓ {f}")
            fixed += 1
        else:
            skipped += 1

    print(f"\n完成: {fixed} 个文件已修复, {skipped} 个无需修改")

if __name__ == "__main__":
    main()
