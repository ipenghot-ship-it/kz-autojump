#!/bin/bash
# 编译脚本：将 .sma 编译为 .amxx
# 用法：./compile.sh [amxxpc路径]

set -e

AMXXPC="${1:-amxxpc}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMA_FILE="$SRC_DIR/kz_autojump.sma"
OUT_FILE="$SRC_DIR/kz_autojump.amxx"
INC_DIR="$SRC_DIR"

if ! command -v "$AMXXPC" &> /dev/null; then
    echo "错误: 找不到 $AMXXPC"
    echo "请安装 AMX Mod X 编译器或指定路径："
    echo "  sudo apt install amxmodx-compiler  # Debian/Ubuntu"
    echo "  或下载：https://www.amxmodx.org/downloads.php"
    exit 1
fi

echo "编译 $SMA_FILE ..."
"$AMXXPC" -i"$INC_DIR" -o"$OUT_FILE" "$SMA_FILE"

if [[ -f "$OUT_FILE" ]]; then
    echo "✓ 编译成功: $OUT_FILE"
    echo "安装: cp $OUT_FILE <cstrike>/addons/amxmodx/plugins/"
    echo "然后在 <cstrike>/addons/amxmodx/configs/plugins.ini 添加: kz_autojump.amxx"
else
    echo "✗ 编译失败"
    exit 1
fi