#!/bin/bash
# DeepSeek Balance - 安装脚本

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="DeepSeekBalance.app"
SRC="$APP_DIR/$APP_NAME"
DEST="/Applications/$APP_NAME"

echo "🚀 DeepSeek Balance 安装中..."

# 如果已运行，先退出
pkill -x DeepSeekBalance 2>/dev/null

# 如果已安装旧版本，先删除
if [ -d "$DEST" ]; then
    rm -rf "$DEST"
    echo "  已删除旧版本"
fi

# 拷贝到 Applications
cp -R "$SRC" "$DEST"
echo "  已拷贝到 /Applications/"

# 移除隔离属性
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null

# 启动
open "$DEST"

echo "✅ 安装完成！"
echo "  右上角菜单栏会出现 DeepSeek 余额图标"
echo "  如果没看到，请点击屏幕右上角 → 找到 💰 图标"
