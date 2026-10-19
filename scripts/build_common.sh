#!/bin/bash
# 打包脚本共用：版本号与后端 release 构建。

# 包版本号以 dub.json 为唯一来源，避免包版本与后端自报版本漂移。
bashub_package_version() {
  local root="${BASHUB_HOME:?BASHUB_HOME not set}"
  local ver
  ver="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/p' \
    "$root/dub.json" | head -n 1)"
  if [ -z "$ver" ]; then
    echo "==========================================================" >&2
    echo "Could not determine version from dub.json" >&2
    echo "==========================================================" >&2
    exit 1
  fi
  printf '%s' "$ver"
}

bashub_prepare_release_build() {
  local root="${BASHUB_HOME:?BASHUB_HOME not set}"
  cd "$root" || exit 1

  echo "bashub: dub clean ..."
  if command -v dub >/dev/null 2>&1; then
    dub clean || true
  fi
  echo "bashub: removing target/d ..."
  rm -rf "$root/target/d"
  mkdir -p "$root/target/d"
  echo "bashub: dub build --build=release-nobounds --compiler=ldc2"
  dub build --build=release-nobounds --compiler=ldc2
}
