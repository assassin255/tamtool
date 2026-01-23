#!/usr/bin/env bash
set -e

ask() {
read -rp "$1" ans
ans="${ans,,}"
if [[ -z "$ans" ]]; then
echo "$2"
else
echo "$ans"
fi
}

choice=$(ask "👉 Bạn có muốn build QEMU 10.2.0 STABLED với LLVM15 tối ưu ULTRA không? (y/n): " "n")

if [[ "$choice" == "y" ]]; then
if [ -x /opt/qemu-optimized/bin/qemu-system-x86_64 ]; then
echo "⚡ QEMU ULTRA đã tồn tại — skip build"
export PATH="/opt/qemu-optimized/bin:$PATH"
else
echo "🚀 Build QEMU 10.2.0 TCG EXTREME"

sudo apt update -y
sudo apt install -y wget gnupg lsb-release software-properties-common build-essential ninja-build git python3 python3-venv python3-pip libglib2.0-dev libpixman-1-dev zlib1g-dev libslirp-dev pkg-config meson aria2 clang-15 lld-15 llvm-15 llvm-15-dev llvm-15-tools

export PATH="/usr/lib/llvm-15/bin:$PATH"
export CC=clang-15
export CXX=clang++-15
export LD=lld-15

python3 -m venv ~/qemu-env
source ~/qemu-env/bin/activate
pip install --upgrade pip tomli packaging

rm -rf /tmp/qemu-src /tmp/qemu-build
cd /tmp
git clone --depth 1 --branch v10.2.0 https://gitlab.com/qemu-project/qemu.git qemu-src
mkdir /tmp/qemu-build
cd /tmp/qemu-build

EXTRA_CFLAGS="-Ofast -march=native -mtune=native -pipe -flto=full -fuse-ld=lld -fno-semantic-interposition -fno-plt -fomit-frame-pointer -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-stack-protector -funsafe-math-optimizations -ffinite-math-only -fno-math-errno -fstrict-aliasing -funroll-loops -finline-functions -finline-hint-functions -DNDEBUG -DDEFAULT_TCG_TB_SIZE=2097152"

LDFLAGS="-flto=full -fuse-ld=lld -Wl,--lto-O3 -Wl,--gc-sections -Wl,--icf=all -Wl,-O3"

../qemu-src/configure \
--prefix=/opt/qemu-optimized \
--target-list=x86_64-softmmu \
--enable-tcg \
--enable-slirp \
--enable-lto \
--enable-coroutine-pool \
--disable-kvm \
--disable-mshv \
--disable-xen \
--disable-gtk \
--disable-sdl \
--disable-spice \
--disable-plugins \
--disable-debug-info \
--disable-docs \
--disable-werror \
--disable-fdt \
CC="$CC" CXX="$CXX" LD="$LD" CFLAGS="$EXTRA_CFLAGS" CXXFLAGS="$EXTRA_CFLAGS" LDFLAGS="$LDFLAGS"

ninja -j"$(nproc)"
sudo ninja install

export PATH="/opt/qemu-optimized/bin:$PATH"
qemu-system-x86_64 --version
echo "🔥 QEMU HEADLESS TCG build xong"
fi
else
echo "⚡ Bỏ qua build QEMU."
fi

echo ""
echo "🪟 Tải Windows Server 2012 R2"

WIN_URL="https://archive.org/download/tamnguyen-2012r2/2012.img"

if [[ ! -f win.img ]]; then
aria2c -x16 -s16 --continue --file-allocation=none "$WIN_URL" -o win.img
fi

read -rp "📦 Mở rộng đĩa thêm bao nhiêu GB (default 20)? " extra_gb
extra_gb="${extra_gb:-20}"
qemu-img resize win.img "+${extra_gb}G"

cpu_host=$(grep -m1 "model name" /proc/cpuinfo | sed 's/^.*: //')
cpu_model="qemu64,pmu=off,model-id=${cpu_host}"

read -rp "⚙ CPU core (default 2): " cpu_core
cpu_core="${cpu_core:-2}"

read -rp "💾 RAM GB (default 4): " ram_size
ram_size="${ram_size:-4}"

echo ""
echo "🔐 Chọn phương thức đăng nhập"
echo "1️⃣ RDP (Remote Desktop)"
echo "2️⃣ VNC (RVNC Viewer)"
read -rp "👉 Nhập số [1-2]: " login_mode

if [[ "$login_mode" == "2" ]]; then
QEMU_DISPLAY="-vnc :0"
TUNNEL_PORT=5900
else
QEMU_DISPLAY="-display none -vga none"
TUNNEL_PORT=3389
fi

qemu-system-x86_64 \
-machine q35 \
-cpu "$cpu_model" \
-smp "$cpu_core" \
-m "${ram_size}G" \
-accel tcg,thread=multi,tb-size=1048576 \
-drive file=win.img,if=virtio,cache=unsafe,aio=threads,format=raw \
-netdev user,id=n0,hostfwd=tcp::3389-:3389 \
-device virtio-net-pci,netdev=n0 \
$QEMU_DISPLAY \
-daemonize \
> /dev/null 2>&1

sleep 3

use_tunnel=$(ask "🛰️ Có muốn public qua tunnel không? (y/n): " "n")

if [[ "$use_tunnel" == "y" ]]; then
wget -q https://github.com/kami2k1/tunnel/releases/latest/download/kami-tunnel-linux-amd64.tar.gz
tar -xzf kami-tunnel-linux-amd64.tar.gz
chmod +x kami-tunnel
sudo apt install -y tmux
tmux kill-session -t kami 2>/dev/null || true
tmux new-session -d -s kami "./kami-tunnel $TUNNEL_PORT"
sleep 2

PUBLIC=$(tmux capture-pane -pt kami -p | sed 's/\x1b\[[0-9;]*m//g' | grep -i 'public' | grep -oE '[a-zA-Z0-9\.\-]+:[0-9]+' | head -n1)

echo "📡 Public Address: $PUBLIC"
echo "💻 Username: administrator"
echo "🔑 Password: Tamnguyenyt@123"
fi
