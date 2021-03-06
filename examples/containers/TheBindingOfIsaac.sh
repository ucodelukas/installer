options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=33 [squash]=1)

packages+=(
        alsa-plugins-pulseaudio
        gtk2
        libcurl
        libGL
        nss
)

packages_buildroot+=(tar unzip)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        $cp "${1:-the_binding_of_isaac_wrath_of_the_lamb-linux-1.48-1355426233.swf.zip}" "$output/BOI.zip"
        test -n "${2-}" && $cp "$2" "$output/flashplayer.tgz" ||
        $curl -L https://fpdownload.macromedia.com/pub/flashplayer/updaters/32/flash_player_sa_linux.x86_64.tar.gz > "$output/flashplayer.tgz"
}

function customize() {
        unzip -p BOI.zip -x '__MACOSX/*' > root/boiwotl.swf
        tar -C root/usr/bin -xzf flashplayer.tgz flashplayer
        rm -f BOI.zip flashplayer.tgz
        mkdir -p root/etc/adobe
        cat << 'EOF' > root/etc/adobe/mms.cfg
AutoUpdateDisable = 1
AVHardwareDisable = 1
OverrideGPUValidation = 1
EOF

        files=(
                /boiwotl.swf /usr/bin/flashplayer /etc/adobe/mms.cfg
                /usr/lib64/libcurl.so.4

                # PulseAudio support
                /etc/alsa /usr/share/alsa/alsa.conf
                /usr/lib64/alsa-lib/libasound_module_{conf,ctl,pcm}_pulse.so
                /usr/share/alsa/alsa.conf.d/50-pulseaudio.conf

                # Container setup
                /usr/bin/{ln,mkdir,sh}
        )
        minimize "${files[@]}"

        cat << 'EOF' > root/init && chmod 0755 root/init
#!/bin/sh -eu
mkdir -p "$HOME/.macromedia"
ln -fns /tmp/save "$HOME/.macromedia/Flash_Player"
exec flashplayer /boiwotl.swf "$@"
EOF

        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/TheBindingOfIsaac" ] ||
mkdir -p "$XDG_DATA_HOME/TheBindingOfIsaac"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/TheBindingOfIsaac:/tmp/save" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir="/home/$USER" \
    --hostname=TheBindingOfIsaac \
    --image="${IMAGE:-TheBindingOfIsaac.img}" \
    --link-journal=no \
    --machine="TheBindingOfIsaac-$USER" \
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

function minimize() {
        local -a requirements

        # Set up required mount points etc. that must exist when read-only.
        mkdir -p root/.SAVE/{bin,etc,dev,home,lib,proc,run,sys,tmp,var}
        ln -fns bin root/.SAVE/sbin
        ln -fns lib root/.SAVE/lib64
        ln -fns . root/.SAVE/usr
        touch root/.SAVE/etc/localtime
        touch root/.SAVE/etc/passwd

        # Assume passwd file user definitions so nspawn can drop privileges.
        echo 'passwd: files' > root/.SAVE/etc/nsswitch.conf
        requirements+=(
                /usr/bin/getent
                /$(cd root ; echo usr/lib*/libnss_files.so.2)
        )

        for path in "$@" "${requirements[@]}"
        do
                mkdir -p "root/.SAVE${path%/*}"

                test -d "root$path" &&
                { cp -at "root/.SAVE${path%/*}" "root$path" ; continue ; }

                { chroot root /usr/bin/ldd "$path" 2>/dev/null || : ; } |
                sed -n 's,^[^/]\+\(/[^ ]*\).*,\1,p' | sort -u |
                while read -rs elf
                do
                        mkdir -p "root/.SAVE${elf%/*}"
                        cp -t "root/.SAVE${elf%/*}" "root$elf"
                done

                cp -t "root/.SAVE${path%/*}" "root$path"
        done

        if mountpoint --quiet root
        then
                rm -fr root/*
                mv -t root root/.SAVE/*
                rmdir root/.SAVE
        else
                mv root root-all
                mv root-all/.SAVE root
        fi
}
