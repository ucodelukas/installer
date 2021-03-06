options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=33 [squash]=1)

packages+=(
        freetype
        libepoxy
        libX{cursor,inerama,randr,ScrnSaver}
        openal-soft
        pulseaudio-libs
        SDL2
)

# Support an option for running on a host with proprietary video drivers.
function initialize_buildroot() if opt nvidia
then
        enable_rpmfusion +nonfree
        packages+=(xorg-x11-drv-nvidia-libs)
else packages+=(libGL mesa-dri-drivers)
fi

packages_buildroot+=({boost,freetype,glm,libepoxy,openal-soft,SDL2}-devel)
packages_buildroot+=(cmake gcc-c++ git-core ImageMagick inkscape make optipng)
packages_buildroot+=(findutils innoextract)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        $cp "${1:-setup_arx_fatalis_1.21_(21994).exe}" "$output/install.exe"
        script << 'EOF'
git clone --branch=master https://github.com/arx/ArxLibertatis.git
mkdir ArxLibertatis/build ; cd ArxLibertatis/build
git reset --hard 20e8f2ac1ec94af9305a956a34cd6231a58b3fb6
cmake -DBUILD_CRASHREPORTER:BOOL=OFF -DCMAKE_INSTALL_PREFIX:PATH=/usr ..
exec make -j"$(nproc)" all
EOF
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

        make -C ArxLibertatis/build install DESTDIR="$PWD/root"
        root/usr/bin/arx-install-data --data-dir=root/usr/share/games/arx --source=install.exe
        rm -f install.exe

        ln -fns usr/bin/arx root/init

        sed "${options[nvidia]:+s, /dev/dri ,&/dev/nvidia* ,}" << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_CONFIG_HOME:=$HOME/.config}/arx" ] ||
mkdir -p "$XDG_CONFIG_HOME/arx"

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/arx" ] ||
mkdir -p "$XDG_DATA_HOME/arx"

exec sudo systemd-nspawn \
    --bind="$XDG_CONFIG_HOME/arx:/home/$USER/.config/arx" \
    --bind="$XDG_DATA_HOME/arx:/home/$USER/.local/share/arx" \
    --bind="+/tmp:/home/$USER/.cache" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir="/home/$USER" \
    --hostname=ArxFatalis \
    --image="${IMAGE:-ArxFatalis.img}" \
    --link-journal=no \
    --machine="ArxFatalis-$USER" \
    --personality=x86-64 \
    --private-network \
    --read-only \
    --setenv="DISPLAY=$DISPLAY" \
    --setenv="HOME=/home/$USER" \
    --setenv=PULSE_COOKIE=/tmp/.pulse/cookie \
    --setenv=PULSE_SERVER=/tmp/.pulse/native \
    --tmpfs=/home \
    --user="$USER" \
    /init "$@"
EOF
}
