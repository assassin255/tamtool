bash -c '
# Cập nhật & cài gói cần thiết
DEBIAN_FRONTEND=noninteractive apt update &&
DEBIAN_FRONTEND=noninteractive apt install -y \
  ubuntu-desktop xfce4 xfce4-goodies \
  tigervnc-standalone-server tigervnc-common dbus-x11 &&

# Tạo thư mục & mật khẩu VNC
mkdir -p ~/.vnc &&
echo 123456 | vncpasswd -f > ~/.vnc/passwd &&
chmod 600 ~/.vnc/passwd &&

# Tạo script khởi động XFCE4 cho VNC
echo "#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4" > ~/.vnc/xstartup &&
chmod +x ~/.vnc/xstartup &&

# Kill session cũ nếu có
vncserver -kill :1 || true &&

# Start TigerVNC (X server + VNC trong 1)
vncserver :1 -geometry 1280x720 -depth 24 &&

echo "TigerVNC chạy tại port 5901 (display :1), password 123456"'
