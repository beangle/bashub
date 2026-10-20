#!/bin/bash
# Debian/Ubuntu 打包脚本。需在 Debian 系系统运行，或安装 dpkg-dev、fakeroot。
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

E=0
LIST=""
fcheck(){
  if ! command -v "$1" >/dev/null 2>&1; then
    LIST=$LIST" "$1
    E=1
  fi
}
fcheck dpkg
fcheck dpkg-deb
fcheck fakeroot
fcheck strip
fcheck ldd
fcheck readlink
fcheck dub
if [ $E -eq 1 ]; then
  ferror "Missing commands on your system:" "$LIST"
fi

bashub_prepare_release_build

MAINTAINER="duantihua <duantihua@163.com>"
VERSION=$(bashub_package_version)
REVISION="1"
[[ -n "$1" ]] && REVISION="$1"

DESTDIR="$BASHUB_HOME/target"
ARCH="amd64"
DEBFILE="bashub_${VERSION}-${REVISION}_${ARCH}.deb"
PKGDIR="$DESTDIR/bashub_${VERSION}-${REVISION}_${ARCH}"

rm -f "$DESTDIR/$DEBFILE"
rm -rf "$PKGDIR"
mkdir -p "$PKGDIR"

pushd "$PKGDIR" > /dev/null

mkdir -p usr/bin usr/lib/systemd/system
cp -f "$BASHUB_HOME/target/d/bashub" usr/bin/bashub
strip --strip-unneeded usr/bin/bashub
cp -f "$BASHUB_HOME/scripts/package/bashub.service" usr/lib/systemd/system/bashub.service

chmod 0755 usr/bin/bashub
chmod 0644 usr/lib/systemd/system/bashub.service

popd > /dev/null

# 从 ELF 直接依赖反推 Debian 包名；在哪个 Debian/Ubuntu 版本构建，就依赖该版本的
# libpq 与 LDC 运行时包，不硬编码会随发行版变化的 SONAME 后缀。
DEB_DEPS="curl"
add_ldd_dep(){
  local soname="$1"
  local path pkg
  path="$(ldd "$BASHUB_HOME/target/d/bashub" | \
    awk -v n="$soname" 'index($1, n) == 1 { print $3; exit }')"
  if [ -z "$path" ] || [ ! -e "$path" ]; then
    return
  fi
  pkg="$(dpkg -S "$(readlink -f "$path")" 2>/dev/null | head -n 1 | cut -d: -f1)"
  if [ -n "$pkg" ]; then
    case ",$DEB_DEPS," in
      *",$pkg,"*) ;;
      *) DEB_DEPS="$DEB_DEPS, $pkg" ;;
    esac
  fi
}
for soname in libc.so.6 libm.so.6 libz.so.1 libgcc_s.so.1 libpq.so.5 \
  libphobos2-ldc-shared.so. libdruntime-ldc-shared.so.; do
  add_ldd_dep "$soname"
done

mkdir -p "$PKGDIR/DEBIAN"

cat > "$PKGDIR/DEBIAN/control" << EOF
Package: bashub
Version: ${VERSION}-${REVISION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Homepage: https://github.com/beangle/bashub
Depends: ${DEB_DEPS}
Description: Beangle BAS console server
 The Beangle BAS console backend.
 .
 Main designer: Duan TiHua
EOF

cat > "$PKGDIR/DEBIAN/preinst" << 'PREINST'
#!/bin/sh
set -e
if ! getent group beangle >/dev/null 2>&1; then
  addgroup --system beangle
fi
if ! getent passwd ems >/dev/null 2>&1; then
  adduser --system --ingroup beangle --home /var/lib/beangle-ems --no-create-home --disabled-login ems 2>/dev/null || \
  useradd -r -g beangle -d /var/lib/beangle-ems -s /usr/sbin/nologin -c "Beangle EMS" ems
else
  usermod -g beangle ems 2>/dev/null || true
fi
if [ ! -d /var/lib/beangle-ems ]; then
  mkdir -p /var/lib/beangle-ems
  chown root:beangle /var/lib/beangle-ems
  chmod 2775 /var/lib/beangle-ems
fi
mkdir -p /var/log/beangle-ems/bashub
PREINST

cat > "$PKGDIR/DEBIAN/postinst" << 'POSTINST'
#!/bin/sh
set -e
chown -R ems:beangle /var/log/beangle-ems/bashub
chmod 2775 /var/log/beangle-ems/bashub
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
POSTINST

cat > "$PKGDIR/DEBIAN/prerm" << 'PRERM'
#!/bin/sh
set -e
if [ "$1" = "remove" ] && command -v systemctl >/dev/null 2>&1; then
  systemctl stop bashub 2>/dev/null || true
fi
PRERM

cat > "$PKGDIR/DEBIAN/postrm" << 'POSTRM'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
POSTRM

chmod 0555 "$PKGDIR/DEBIAN/preinst" "$PKGDIR/DEBIAN/postinst" \
  "$PKGDIR/DEBIAN/prerm" "$PKGDIR/DEBIAN/postrm"

fakeroot dpkg-deb --build -Zxz "$PKGDIR" "$DESTDIR/$DEBFILE" 2>/dev/null || \
fakeroot dpkg-deb --build "$PKGDIR" "$DESTDIR/$DEBFILE"

rm -rf "$PKGDIR"

echo "Built: $DESTDIR/$DEBFILE"
