#!/bin/bash
# Build script for creating AppImage

set -e

APPDIR="wry-zig-wrapper.AppDir"
APPIMAGE="wry-zig-wrapper-x86_64.AppImage"

# Download appimagetool if not available
if [ ! -f /tmp/appimagetool ]; then
    echo "Downloading appimagetool..."
    wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O /tmp/appimagetool
    chmod +x /tmp/appimagetool
fi

# Create AppDir structure
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy binaries
cp zig-out/bin/wry_window_app "$APPDIR/usr/bin/"
cp zig-out/lib/libwry_zig_wrapper.so "$APPDIR/usr/lib/"

# Create AppRun
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/share}"
exec "${HERE}/usr/bin/wry_window_app" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Create desktop file
cat > "$APPDIR/wry-zig-wrapper.desktop" << 'EOF'
[Desktop Entry]
Name=Wry Zig Wrapper
Comment=File Browser built with Zig and Wry
Exec=wry_zig_wrapper
Icon=wry-zig-wrapper
Type=Application
Categories=Utility;FileTools;
Terminal=false
StartupNotify=true
EOF
cp "$APPDIR/wry-zig-wrapper.desktop" "$APPDIR/usr/share/applications/"

# Create icon
cat > "$APPDIR/wry-zig-wrapper.svg" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
    <defs>
        <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#667eea;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#764ba2;stop-opacity:1" />
        </linearGradient>
    </defs>
    <rect width="256" height="256" rx="40" fill="url(#grad1)"/>
    <text x="128" y="128" font-family="Arial, sans-serif" font-size="80" font-weight="bold" fill="white" text-anchor="middle" dominant-baseline="middle">Wry</text>
    <rect x="76" y="150" width="104" height="65" rx="10" fill="rgba(255,255,255,0.3)"/>
    <text x="128" y="190" font-family="monospace" font-size="20" fill="white" text-anchor="middle">Zig + Rust</text>
</svg>
EOF
cp "$APPDIR/wry-zig-wrapper.svg" "$APPDIR/usr/share/icons/hicolor/256x256/apps/"

# Build AppImage
echo "Building AppImage..."
/tmp/appimagetool "$APPDIR" "$APPIMAGE"

echo "AppImage created: $APPIMAGE"
echo "Test with: ./$APPIMAGE"
