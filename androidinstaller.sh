#!/usr/bin/env bash
set -e

silent() {
"$@" > /dev/null 2>&1
}

ask() {
read -rp "$1" ans
ans="${ans,,}"
if [[ -z "$ans" ]]; then
echo "$2"
else
echo "$ans"
fi
}

choice=$(ask "👉 Bạn có muốn build QEMU để tạo VM với tăng tốc LLVM không ? (y/n): " "n")

if [[ "$choice" == "y" ]]; then
if [ -x /opt/qemu-optimized/bin/qemu-system-x86_64 ]; then
echo "⚡ QEMU ULTRA đã tồn tại — skip build"
export PATH="/opt/qemu-optimized/bin:$PATH"
else
echo "🚀 Đang tải apt cần thiết"

OS_ID="$(. /etc/os-release && echo "$ID")"
OS_VER="$(. /etc/os-release && echo "$VERSION_ID")"

if [[ "$OS_ID" == "debian" && "$OS_VER" == "13" ]]; then
LLVM_VER=19
else
LLVM_VER=15
fi

silent sudo apt update
silent sudo apt install -y wget gnupg build-essential ninja-build git python3 python3-venv python3-pip libglib2.0-dev libpixman-1-dev zlib1g-dev libslirp-dev pkg-config meson aria2 clang-$LLVM_VER lld-$LLVM_VER llvm-$LLVM_VER llvm-$LLVM_VER-dev llvm-$LLVM_VER-tools

export PATH="/usr/lib/llvm-$LLVM_VER/bin:$PATH"
export CC="clang-$LLVM_VER"
export CXX="clang++-$LLVM_VER"
export LD="lld-$LLVM_VER"

python3 -m venv ~/qemu-env
source ~/qemu-env/bin/activate
silent pip install --upgrade pip tomli packaging

rm -rf /tmp/qemu-src /tmp/qemu-build
cd /tmp
silent git clone --depth 1 --branch v10.2.0 https://gitlab.com/qemu-project/qemu.git qemu-src
mkdir /tmp/qemu-build
cd /tmp/qemu-build

EXTRA_CFLAGS="-Ofast -march=native -mtune=native -pipe -flto=full -fuse-ld=lld -fno-semantic-interposition -fno-plt -fomit-frame-pointer -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-stack-protector -funsafe-math-optimizations -ffinite-math-only -fno-math-errno -fstrict-aliasing -funroll-loops -finline-functions -finline-hint-functions -DNDEBUG -DDEFAULT_TCG_TB_SIZE=2097152"
LDFLAGS="-flto=full -fuse-ld=lld -Wl,--lto-O3 -Wl,--gc-sections -Wl,--icf=all -Wl,-O3"
echo "🔁 Đang Biên Dịch..."
silent ../qemu-src/configure \
--prefix=/opt/qemu-optimized \
--target-list=x86_64-softmmu \
--enable-tcg \
--enable-slirp \
--enable-lto \
--enable-coroutine-pool \
--disable-kvm \
--disable-mshv \
--disable-xen \
--disable-spice \
--disable-plugins \
--disable-debug-info \
--disable-docs \
--disable-werror \
CC="$CC" CXX="$CXX" LD="$LD" CFLAGS="$EXTRA_CFLAGS" CXXFLAGS="$EXTRA_CFLAGS" LDFLAGS="$LDFLAGS"
echo "🕧 QEMU đang được build vui lòng đợi... ( Có thể sẽ khá lâu )"
silent ninja -j"$(nproc)"
silent sudo ninja install

export PATH="/opt/qemu-optimized/bin:$PATH"
qemu-system-x86_64 --version
echo "🔥 QEMU LLVM đã build xong"
fi
else
echo "⚡ Bỏ qua build QEMU."
fi

echo ""
echo " Chọn phiên bản Android muốn tải:"
echo "1️⃣ Android 9 x86-64"
read -rp "👉 Nhập số [1-1]: " win_choice

case "$win_choice" in
1) WIN_NAME="Android 9 x86-64"; WIN_URL="https://archive.org/download/android-x86_64-9.0-r2_202106/android-x86_64-9.0-r2.iso" ;;
2) WIN_NAME="Windows Server 2022"; WIN_URL="https://archive.org/download/tamnguyen-2022/2022.img" ;;
*) WIN_NAME="Android 9 x86-64"; WIN_URL="https://archive.org/download/android-x86_64-9.0-r2_202106/android-x86_64-9.0-r2.iso" ;;
esac
echo "🪟 Đang Tải $WIN_NAME..."
if [[ ! -f win.img ]]; then
silent aria2c -x16 -s16 --continue --file-allocation=none "$WIN_URL" -o win.img
fi

read -rp "📦 Tạo disk với bao nhiêu GB (default 50)? " extra_gb
extra_gb="${extra_gb:-50}"
silent qemu-img create -f qcow2 disk.qcow2 "${extra_gb}G"

cpu_host=$(grep -m1 "model name" /proc/cpuinfo | sed 's/^.*: //')
cpu_model="qemu64,hypervisor=off,pmu=off,l3-cache=on,+cmov,+mmx,+fxsr,+sse2,+ssse3,+sse4.1,+sse4.2,+popcnt,+aes,+cx16,+x2apic,+sep,+pat,+pse,model-id=${cpu_host}"

read -rp "⚙ CPU core (default 4): " cpu_core
cpu_core="${cpu_core:-4}"

read -rp "💾 RAM GB (default 4): " ram_size
ram_size="${ram_size:-4}"

qemu-system-x86_64 \
-machine q35,hpet=off \
-cpu "$cpu_model",vmx=off,hypervisor=off \
-smp "$cpu_core" \
-m "${ram_size}G" \
--rtc base=utc \
-device ich9-ahci \
-drive file=disk.qcow2,if=none,id=disk0,format=qcow2,cache=unsafe,aio=threads \
-netdev user,id=n0 \
-device e1000,netdev=n0 \
-vga std \
-device qemu-xhci \
-device usb-kbd \
-device usb-tablet \
-vnc :0 \
-boot order=d,menu=on \
-cdrom android.iso \
-no-user-config \
-daemonize
sleep 3

use_rdp=$(ask "🛰️ Tiếp tục mở port để kết nối đến VM? (y/n): " "n")
echo "⌛ Đang Tạo VM với cấu hình bạn đã nhập vui lòng đợi..."
if [[ "$use_rdp" == "y" ]]; then
silent wget https://github.com/kami2k1/tunnel/releases/latest/download/kami-tunnel-linux-amd64.tar.gz
silent tar -xzf kami-tunnel-linux-amd64.tar.gz
silent chmod +x kami-tunnel
silent sudo apt install -y tmux

tmux kill-session -t kami 2>/dev/null || true
tmux new-session -d -s kami "./kami-tunnel 5900"
sleep 4

PUBLIC=$(tmux capture-pane -pt kami -p | sed 's/\x1b\[[0-9;]*m//g' | grep -i 'public' | grep -oE '[a-zA-Z0-9\.\-]+:[0-9]+' | head -n1)

echo ""
echo "══════════════════════════════════════════════"
echo "🚀  VM DEPLOYED SUCCESSFULLY"
echo "══════════════════════════════════════════════"
echo "🐧 OS          : $WIN_NAME"
echo "⚙ CPU Cores   : $cpu_core"
echo "💾 RAM         : ${ram_size} GB"
echo "──────────────────────────────────────────────"
echo "📡 VNC Address : $PUBLIC"
echo "══════════════════════════════════════════════"
echo "🟢 Status      : RUNNING"
echo "⏱ GUI Mode   : VNC/Headless"
echo "══════════════════════════════════════════════"
fi
