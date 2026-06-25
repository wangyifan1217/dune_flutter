#!/usr/bin/env bash
#
# 启动安卓调试（bash / git-bash）
# 用法：
#   ./run-android.sh                # 自动选择第一台安卓设备
#   ./run-android.sh 253408e4       # 指定设备 id
#   ./run-android.sh -r             # 以 release 模式运行
#
# 说明：本机 pub cache 默认路径含中文，会导致 jni 等插件原生(CMake/Ninja)构建失败，
# 这里强制把 PUB_CACHE 指到纯英文路径 D:\pubcache 规避该问题。

set -e

# 关键：英文 pub cache 路径，避免原生构建因中文路径失败
export PUB_CACHE="D:\\pubcache"

# 切到脚本所在目录（Flutter 工程根，含 pubspec.yaml）
cd "$(dirname "$0")"

MODE="--debug"
DEVICE=""
for arg in "$@"; do
  case "$arg" in
    -r|--release) MODE="--release" ;;
    *) DEVICE="$arg" ;;
  esac
done

# 未指定设备时，自动挑选一台安卓设备
if [ -z "$DEVICE" ]; then
  DEVICE=$(flutter devices --machine \
    | grep -o '"id":"[^"]*"[^}]*"targetPlatform":"android[^"]*"' \
    | head -n1 | sed -E 's/.*"id":"([^"]*)".*/\1/')
fi

if [ -z "$DEVICE" ]; then
  echo "未找到可用安卓设备，请先连接设备或启动模拟器。"
  flutter devices
  exit 1
fi

echo "PUB_CACHE = $PUB_CACHE"
echo "启动调试：设备=$DEVICE 模式=$MODE"

flutter run -d "$DEVICE" "$MODE"
