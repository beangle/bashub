#!/bin/bash
# RPM 打包脚本。需在 Fedora/RHEL 系系统运行，并安装 rpm-build、fakeroot。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BASHUB_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BASHUB_HOME"

set -e -o pipefail
# shellcheck source=build_common.sh
source "$SCRIPT_DIR/build_common.sh"

ferror(){
  echo "==========================================================" >&2
  echo "$1" >&2
  echo "$2" >&2
  echo "==========================================================" >&2
  exit 1
}

# rpm 4.14 起才写入 SHA256HEADER；旧版 rpmbuild 只能写 SHA1 头摘要，
# 这种包会被要求 SHA256 摘要的新版 rpm 拒绝为 “does not verify: no digest”。
require_modern_rpmbuild(){
  local version
  version="$(rpmbuild --version | awk '{print $3}')"
  if [ -z "$version" ] || \
    [ "$(printf '%s\n%s\n' "$version" "4.14" | sort -V | head -n 1)" != "4.14" ]; then
    ferror "rpmbuild >= 4.14 is required (found ${version:-unknown})" \
      "A newer rpmbuild is required to emit SHA256HEADER; put it first in PATH."
  fi
}

sys_release_version(){
  local os_id
  os_id=$(source /etc/os-release && echo "$ID")
  if [ "$os_id" = "fedora" ]; then
    REVISION="1.fc$(source /etc/os-release && echo "$VERSION_ID")"
  else
    REVISION="1.el$(source /etc/os-release && echo "$VERSION_ID")"
  fi
}

E=0
LIST=""
fcheck(){
  if ! command -v "$1" >/dev/null 2>&1; then
    LIST=$LIST" "$1
    E=1
  fi
}
fcheck rpmbuild
fcheck fakeroot
fcheck strip
fcheck dub
if [ $E -eq 1 ]; then
  ferror "Missing commands on your system:" "$LIST"
fi
require_modern_rpmbuild

bashub_prepare_release_build

MAINTAINER="duantihua <duantihua@163.com>"
VENDOR="Beangle"
VERSION=$(bashub_package_version)
REVISION=""
[[ -n "$1" ]] && REVISION="$1"
if [ -z "$REVISION" ]; then
  sys_release_version
fi

DESTDIR="$BASHUB_HOME/target"
RPMVERSION=${VERSION//-/\~}
ARCH="x86_64"
PKGDIR="bashub-${RPMVERSION}-${REVISION}.${ARCH}"
RPMFILE="bashub-${RPMVERSION}-${REVISION}.${ARCH}.rpm"
RPMDIR="$DESTDIR/rpmbuild"

rm -f "$DESTDIR/$RPMFILE"
rm -rf "$DESTDIR/$PKGDIR" "$RPMDIR" "$DESTDIR/bashub.spec"
mkdir -p "$DESTDIR/$PKGDIR"

pushd "$DESTDIR/$PKGDIR" > /dev/null

mkdir -p usr/bin usr/lib/systemd/system
cp -f "$BASHUB_HOME/target/d/bashub" usr/bin/bashub
strip --strip-unneeded usr/bin/bashub
cp -f "$BASHUB_HOME/scripts/package/bashub.service" usr/lib/systemd/system/bashub.service

chmod 0755 usr/bin/bashub
chmod 0644 usr/lib/systemd/system/bashub.service

cd ..

cat > bashub.spec <<EOF
Name: bashub
Version: ${RPMVERSION}
Release: ${REVISION}
Summary: Beangle BAS console server
Group: Applications/System
License: GPL-3.0-or-later
URL: https://github.com/beangle/bashub
Vendor: ${VENDOR}
Packager: ${MAINTAINER}
ExclusiveArch: ${ARCH}
Requires: curl
Provides: bashub(${ARCH}) = ${RPMVERSION}-${REVISION}

%description
The Beangle BAS console backend.
Main designer: Duan TiHua

%pre
getent group beangle >/dev/null 2>&1 || groupadd -r beangle
if ! getent passwd ems >/dev/null 2>&1; then
  useradd -r -g beangle -d /var/lib/beangle-ems -s /sbin/nologin -c "Beangle EMS" ems
else
  usermod -g beangle ems 2>/dev/null || :
fi
if [ ! -d /var/lib/beangle-ems ]; then
  mkdir -p /var/lib/beangle-ems
  chown root:beangle /var/lib/beangle-ems
  chmod 2775 /var/lib/beangle-ems
fi
mkdir -p /var/log/beangle-ems/bashub

%post
chown -R ems:beangle /var/log/beangle-ems/bashub
chmod 2775 /var/log/beangle-ems/bashub
systemctl daemon-reload 2>/dev/null || :

%preun
if [ "\$1" = 0 ]; then
  systemctl stop bashub 2>/dev/null || :
fi

%postun
systemctl daemon-reload 2>/dev/null || :

%files
EOF

# /var 下的数据目录不在 %files 中，升级和卸载都会保留。
find "$DESTDIR/$PKGDIR" ! -type d | \
  sed "s|$DESTDIR/$PKGDIR|/|" >> "$DESTDIR/bashub.spec"

DATE=$(LC_ALL=C date '+%a %b %d %Y')
cat >> "$DESTDIR/bashub.spec" <<EOF

%changelog
* $DATE $MAINTAINER - ${RPMVERSION}-${REVISION}
- Beangle BAS console server
EOF

mkdir -p "$RPMDIR"
sed -i "1i %define _rpmdir $RPMDIR" "$DESTDIR/bashub.spec"
fakeroot rpmbuild --quiet --buildroot="$DESTDIR/$PKGDIR" -bb --target "$ARCH" \
  --define '_binary_payload w9.xzdio' \
  --define '_binary_filedigest_algorithm 8' \
  --define '_source_filedigest_algorithm 8' "$DESTDIR/bashub.spec"

popd > /dev/null
mv "$RPMDIR/$ARCH/bashub-$RPMVERSION-$REVISION.$ARCH.rpm" "$DESTDIR/$RPMFILE"
rm -rf "$RPMDIR" "$DESTDIR/$PKGDIR" "$DESTDIR/bashub.spec"

RPMVERIFY="$(LC_ALL=C rpm -Kv "$DESTDIR/$RPMFILE" 2>&1 || true)"
if ! grep -q 'Header SHA256 digest: OK' <<<"$RPMVERIFY"; then
  ferror "Generated RPM has no SHA256 header digest" "$RPMVERIFY"
fi

echo "Built: $DESTDIR/$RPMFILE"
