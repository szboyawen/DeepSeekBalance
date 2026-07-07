#!/bin/bash
cd "$(dirname "$0")"
echo "=== DeepSeek Balance -> GitHub ==="
echo ""
git add -A
git commit -m "Update files before push"
echo ""
echo "正在推送代码..."
git push -u origin main
echo ""
echo "✅ 完成！按回车键退出..."
read
