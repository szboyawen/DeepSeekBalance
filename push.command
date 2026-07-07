#!/bin/bash
cd "$(dirname "$0")"
echo "正在推送代码到 GitHub..."
git push -u origin main
echo ""
echo "按回车键退出..."
read
