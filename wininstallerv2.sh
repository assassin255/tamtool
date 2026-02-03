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
echo "🚀 Đang Tải Các Apt Cần Thiết..."

OS_ID="$(. /etc/os-release && echo "$ID")"
OS_VER="$(. /etc/os-release && echo "$VERSION_ID")"

if [[ "$OS_ID" == "debian" && "$OS_VER" == "13" ]]; then
LLVM_VER=19
else
LLVM_VER=15
fi

silent sudo apt update
silent sudo apt install -y wget gnupg build-essential ninja-build git python3 python3-venv python3-pip libglib2.0-dev libpixman-1-dev zlib1g-dev ovmf libslirp-dev pkg-config meson aria2 clang-$LLVM_VER lld-$LLVM_VER llvm-$LLVM_VER llvm-$LLVM_VER-dev llvm-$LLVM_VER-tools

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
--disable-gtk \
--disable-sdl \
--disable-spice \
--disable-vnc \
--disable-plugins \
--disable-debug-info \
--disable-docs \
--disable-werror \
--disable-fdt \
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
echo "🪟 Chọn phiên bản Windows muốn tải:"
echo "1️⃣ Windows Server 2012 R2"
echo "2️⃣ Windows Server 2022"
echo "3️⃣ Windows 11 LTSB"
read -rp "👉 Nhập số [1-3]: " win_choice

case "$win_choice" in
1) WIN_NAME="Windows Server 2012 R2"; WIN_URL="https://archive.org/download/tamnguyen-2012r2/2012.img" ;;
2) WIN_NAME="Windows Server 2022"; WIN_URL="https://archive.org/download/tamnguyen-2022/2022.img" ;;
3) WIN_NAME="Windows Server 2025 LTSB"; WIN_URL="https://archive.org/download/tamdz-w-11/TamdzW11.img" ;;
*) WIN_NAME="Windows Server 2012 R2"; WIN_URL="https://archive.org/download/tamnguyen-2012r2/2012.img" ;;
esac
echo "🪟 Đang Tải $WIN_NAME..."
if [[ ! -f win.img ]]; then
silent aria2c -x16 -s16 --continue --file-allocation=none "$WIN_URL" -o win.img
fi

read -rp "📦 Mở rộng đĩa thêm bao nhiêu GB (default 20)? " extra_gb
extra_gb="${extra_gb:-20}"
silent qemu-img resize win.img "+${extra_gb}G"

cpu_host=$(grep -m1 "model name" /proc/cpuinfo | sed 's/^.*: //')
cpu_model="qemu64,hypervisor=off,pmu=off,l3-cache=on,+cmov,+mmx,+fxsr,+sse2,+ssse3,+sse4.1,+sse4.2,+popcnt,+aes,+cx16,+x2apic,+sep,+pat,+pse,model-id=${cpu_host}"

read -rp "⚙ CPU core (default 4): " cpu_core
cpu_core="${cpu_core:-4}"

read -rp "💾 RAM GB (default 4): " ram_size
ram_size="${ram_size:-4}"

cp /usr/share/OVMF/OVMF_VARS.fd ./OVMF_VARS.fd && \
qemu-system-x86_64 \
-machine q35,hpet=off \
-cpu "$cpu_model" \
-smp "$cpu_core" \
-m "${ram_size}G" \
-accel tcg,thread=multi,tb-size=2097152 \
-rtc base=localtime \
-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
-drive if=pflash,format=raw,file=OVMF_VARS.fd \
-drive file=win.img,if=virtio,cache=unsafe,aio=threads,format=raw \
-netdev user,id=n0,hostfwd=tcp::3389-:3389 \
-device virtio-net-pci,netdev=n0 \
-nodefaults \
-smbios type=1,manufacturer="Dell Inc.",product="PowerEdge R640" \
-global kvm-pit.lost_tick_policy=discard \
-no-user-config \
-display none \
-vga none \
-serial none \
-parallel none \
-daemonize
> /dev/null 2>&1 || true
sleep 3

use_rdp=$(ask "🛰️ Tiếp tục mở port để kết nối đến VM? (y/n): " "n")
echo "⌛ Đang Tạo VM với cấu hình bạn đã nhập vui lòng đợi..."
if [[ "$use_rdp" == "y" ]]; then
silent wget https://github.com/kami2k1/tunnel/releases/latest/download/kami-tunnel-linux-amd64.tar.gz
silent tar -xzf kami-tunnel-linux-amd64.tar.gz
silent chmod +x kami-tunnel
silent sudo apt install -y tmux

tmux kill-session -t kami 2>/dev/null || true
tmux new-session -d -s kami "./kami-tunnel 3389"
sleep 4

PUBLIC=$(tmux capture-pane -pt kami -p | sed 's/\x1b\[[0-9;]*m//g' | grep -i 'public' | grep -oE '[a-zA-Z0-9\.\-]+:[0-9]+' | head -n1)

echo ""
echo "══════════════════════════════════════════════"
echo "🚀 WINDOWS VM DEPLOYED SUCCESSFULLY"
echo "══════════════════════════════════════════════"
echo "🪟 OS          : $WIN_NAME"
echo "⚙ CPU Cores   : $cpu_core"
echo "💾 RAM         : ${ram_size} GB"
echo "🧠 CPU Host    : $cpu_host"
echo "──────────────────────────────────────────────"
echo "📡 RDP Address : $PUBLIC"
echo "👤 Username    : administrator"
echo "🔑 Password    : Tamnguyenyt@123"
echo "══════════════════════════════════════════════"
echo "🟢 Status      : RUNNING"
echo "⏱ GUI Mode   : Headless / RDP"
echo "══════════════════════════════════════════════"
fi
