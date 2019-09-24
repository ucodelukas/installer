options+=([arch]=i686 [distro]=fedora [nspawn]=1 [release]=30 [squash]=1)

packages+=(
        mesa-dri-drivers
        wine-core
        wine-pulseaudio
)

packages_buildroot+=(innoextract)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        $cp "${1:-setup_beyond_good_and_evil_2.1.0.9.exe}" "$output/install.exe"
}

function customize() {
        exclude_paths+=(
                root
                usr/{include,lib/debug,local,src}
                usr/{lib,share}/locale
                usr/lib/{systemd,tmpfiles.d}
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
        )

        (cd root/root ; exec innoextract ../../install.exe)
        rm -fr install.exe root/root/app/{gog*,__support,webcache.zip}
        mv root/root/app root/BGE

        cat << 'EOG' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/BeyondGoodAndEvil" ] ||
mkdir -p "$XDG_DATA_HOME/BeyondGoodAndEvil"

exec sudo systemd-nspawn \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/BGE \
    --hostname=BeyondGoodAndEvil \
    --image="${IMAGE:-BeyondGoodAndEvil.img}" \
    --link-journal=no \
    --machine="BeyondGoodAndEvil-$USER" \
    --overlay="+/BGE:$XDG_DATA_HOME/BeyondGoodAndEvil:/BGE" \
    --personality=x86 \
    --private-network \
    --read-only \
    --setenv="DISPLAY=$DISPLAY" \
    --setenv="HOME=/home/$USER" \
    --setenv=PULSE_COOKIE=/tmp/.pulse/cookie \
    --setenv=PULSE_SERVER=/tmp/.pulse/native \
    --tmpfs=/home \
    --user="$USER" \
    /bin/sh -euo pipefail /dev/stdin "$@" << 'EOF'
(unset DISPLAY
wine reg add 'HKEY_CURRENT_USER\Software\Ubisoft\Beyond Good & Evil\SettingsApplication.INI\Basic video' /v 'NoBands' /t REG_DWORD /d 1 /f
wine /BGE/SettingsApplication.exe
exec sleep 1)
exec wine /BGE/BGE.exe "$@"
EOF
EOG
}
