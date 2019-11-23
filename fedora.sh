packages=(glibc-minimal-langpack)
packages_buildroot=(glibc-minimal-langpack)

DEFAULT_RELEASE=31

function create_buildroot() {
        local -r cver=$(test "x${options[release]-}" = x30 && echo 1.2 || echo 1.9)
        local -r image="https://dl.fedoraproject.org/pub/fedora/linux/releases/${options[release]:=$DEFAULT_RELEASE}/Container/$DEFAULT_ARCH/images/Fedora-Container-Base-${options[release]}-$cver.$DEFAULT_ARCH.tar.xz"

        opt bootable && packages_buildroot+=(kernel-core microcode_ctl)
        opt bootable && opt squash && packages_buildroot+=(kernel-modules)
        opt executable && opt uefi && packages_buildroot+=(dosfstools)
        opt selinux && packages_buildroot+=(busybox kernel-core policycoreutils qemu-system-x86-core)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt verity && packages_buildroot+=(veritysetup)
        opt uefi && packages_buildroot+=(binutils fedora-logos ImageMagick) &&
        opt sb_cert && opt sb_key && packages_buildroot+=(nss-tools openssl pesign)
        packages_buildroot+=(e2fsprogs)

        $mkdir -p "$buildroot"
        $curl -L "${image%-Base*}-${options[release]}-$cver-$DEFAULT_ARCH-CHECKSUM" > "$output/checksum"
        $curl -L "$image" > "$output/image.tar.xz"
        verify_distro "$output/checksum" "$output/image.tar.xz"
        $tar -xJOf "$output/image.tar.xz" '*/layer.tar' | $tar -C "$buildroot" -x
        $rm -f "$output/checksum" "$output/image.tar.xz"

        configure_initrd_generation

        # Disable bad packaging options.
        $sed -i -e '/^[[]main]/ainstall_weak_deps=False' "$buildroot/etc/dnf/dnf.conf"
        $sed -i -e 's/^enabled=1.*/enabled=0/' "$buildroot"/etc/yum.repos.d/*modular*.repo

        enter /usr/bin/dnf --assumeyes upgrade
        enter /usr/bin/dnf --assumeyes install "${packages_buildroot[@]}" "$@"

        # Let the configuration decide if the system should have documentation.
        $sed -i -e '/^tsflags=/d' "$buildroot/etc/dnf/dnf.conf"
}

function install_packages() {
        opt bootable || opt networkd && packages+=(systemd)
        opt selinux && packages+=(selinux-policy-targeted)

        mkdir -p root/var/cache/dnf
        mount --bind /var/cache/dnf root/var/cache/dnf
        trap -- 'umount root/var/cache/dnf ; trap - RETURN' RETURN

        dnf --assumeyes --installroot="$PWD/root" \
            ${options[arch]:+--forcearch="${options[arch]}"} \
            --releasever="${options[release]}" \
            install "${packages[@]:-filesystem}" "$@"

        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function distro_tweaks() {
        exclude_paths+=('usr/lib/.build-id')

        rm -fr root/etc/inittab root/etc/rc.d

        test -x root/usr/bin/update-crypto-policies &&
        chroot root /usr/bin/update-crypto-policies --set FUTURE

        test -s root/etc/dnf/dnf.conf &&
        sed -i -e '/^[[]main]/ainstall_weak_deps=False' root/etc/dnf/dnf.conf

        compgen -G 'root/etc/yum.repos.d/*modular*.repo' &&
        sed -i -e 's/^enabled=1.*/enabled=0/' root/etc/yum.repos.d/*modular*.repo

        test -s root/etc/gdm/custom.conf &&
        sed -i -e '/WaylandEnable=false$/s/^[# ]*//' root/etc/gdm/custom.conf

        test -s root/usr/share/glib-2.0/schemas/org.gnome.shell.gschema.xml &&
        cat << 'EOF' > root/usr/share/glib-2.0/schemas/99_fix.brain.damage.gschema.override
[org.gnome.calculator]
angle-units='radians'
button-mode='advanced'
[org.gnome.Charmap.WindowState]
maximized=true
[org.gnome.desktop.a11y]
always-show-universal-access-status=true
[org.gnome.desktop.calendar]
show-weekdate=true
[org.gnome.desktop.input-sources]
xkb-options=['compose:rwin','ctrl:nocaps','grp_led:caps']
[org.gnome.desktop.interface]
clock-format='24h'
clock-show-date=true
clock-show-seconds=true
clock-show-weekday=true
[org.gnome.desktop.media-handling]
automount=false
automount-open=false
autorun-never=true
[org.gnome.desktop.notifications]
show-in-lock-screen=false
[org.gnome.desktop.peripherals.keyboard]
numlock-state=true
[org.gnome.desktop.peripherals.touchpad]
natural-scroll=true
tap-to-click=true
[org.gnome.desktop.privacy]
hide-identity=true
recent-files-max-age=0
remember-app-usage=false
remember-recent-files=false
send-software-usage-stats=false
show-full-name-in-top-bar=false
[org.gnome.desktop.screensaver]
show-full-name-in-top-bar=false
user-switch-enabled=false
[org.gnome.desktop.session]
idle-delay=0
[org.gnome.desktop.wm.keybindings]
cycle-windows=['<Alt>Escape','<Alt>Tab']
cycle-windows-backward=['<Shift><Alt>Escape','<Shift><Alt>Tab']
panel-main-menu=['<Super>s','<Alt>F1','XF86LaunchA']
panel-run-dialog=['<Super>r','<Alt>F2']
show-desktop=['<Super>d']
switch-applications=['<Super>Tab']
switch-applications-backward=['<Shift><Super>Tab']
[org.gnome.desktop.wm.preferences]
button-layout='menu:minimize,maximize,close'
focus-mode='sloppy'
mouse-button-modifier='<Alt>'
visual-bell=true
[org.gnome.eog.ui]
statusbar=true
[org.gnome.Evince.Default]
continuous=false
sizing-mode='fit-page'
[org.gnome.settings-daemon.plugins.media-keys]
max-screencast-length=0
on-screen-keyboard=['<Super>k']
[org.gnome.settings-daemon.plugins.power]
ambient-enabled=false
idle-dim=false
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
[org.gnome.settings-daemon.plugins.xsettings]
antialiasing='rgba'
hinting='full'
[org.gnome.shell]
always-show-log-out=true
favorite-apps=['firefox.desktop','vlc.desktop','gnome-terminal.desktop']
[org.gnome.shell.keybindings]
toggle-application-view=['<Super>a','XF86LaunchB']
[org.gnome.shell.overrides]
focus-change-on-pointer-rest=false
workspaces-only-on-primary=false
[org.gnome.Terminal.Legacy.Keybindings]
full-screen='disabled'
help='disabled'
[org.gnome.Terminal.Legacy.Settings]
default-show-menubar=false
menu-accelerator-enabled=false
[org.gnome.Terminal.Legacy.Profile]
background-color='#000000'
background-transparency-percent=20
foreground-color='#FFFFFF'
login-shell=true
scrollback-lines=100000
scrollback-unlimited=false
scrollbar-policy='never'
use-transparent-background=true
use-theme-colors=false
EOF

        sed -i -e 's/^[^#]*PS1="./&\\$? /;s/mask 002$/mask 022/' root/etc/bashrc
}

function save_boot_files() if opt bootable
then
        test -s vmlinuz || cp -pt . /lib/modules/*/vmlinuz
        test -s initrd.img || cp -p /boot/initramfs-* initrd.img
        opt selinux && test ! -s vmlinuz.relabel && ln -fn vmlinuz vmlinuz.relabel
        opt uefi && test ! -s logo.bmp && convert -background none /usr/share/fedora-logos/fedora_logo.svg -trim -color-matrix '0 1 0 0 0 0 1 0 0 0 0 1 1 0 0 0' logo.bmp
        test -s os-release || cp -pt . root/etc/os-release
elif opt selinux
then test -s vmlinuz.relabel || cp -p /lib/modules/*/vmlinuz vmlinuz.relabel
fi

function configure_initrd_generation() if opt bootable
then
        # Don't expect that the build system is the target system.
        $mkdir -p "$buildroot/etc/dracut.conf.d"
        echo 'hostonly="no"' > "$buildroot/etc/dracut.conf.d/99-settings.conf"

        # The initrd build script won't run without an ID since Fedora 31.
        if ! test -s "$buildroot/etc/machine-id"
        then
                local -r container_id=$(</proc/sys/kernel/random/uuid)
                echo "${container_id//-}" > "$buildroot/etc/machine-id"
        fi

        # Load NVMe support before verity so dm-init can find the partition.
        if opt nvme
        then
                $mkdir -p "$buildroot/etc/modprobe.d"
                echo > "$buildroot/etc/modprobe.d/nvme-verity.conf" \
                    'softdep dm-verity pre: nvme'
                echo >> "$buildroot/etc/dracut.conf.d/99-nvme-verity.conf" \
                    'install_optional_items+=" /etc/modprobe.d/nvme-verity.conf "'
        fi

        # Since systemd can't skip canonicalization, wait for a udev hack.
        if opt verity
        then
                local dropin=/usr/lib/systemd/system/sysroot.mount.d
                $mkdir -p "$buildroot$dropin"
                echo > "$buildroot$dropin/verity-root.conf" '[Unit]
After=dev-mapper-root.device
Requires=dev-mapper-root.device'
                echo >> "$buildroot/etc/dracut.conf.d/99-settings.conf" \
                    "install_optional_items+=\" $dropin/verity-root.conf \""
        fi

        # Create a generator to handle verity ramdisks since dm-init can't.
        opt verity && if opt ramdisk
        then
                local -r gendir=/usr/lib/systemd/system-generators
                $mkdir -p "$buildroot$gendir"
                echo > "$buildroot$gendir/dmsetup-verity-root" '#!/bin/bash -eu
read -rs cmdline < /proc/cmdline
test "x${cmdline}" != "x${cmdline%%DVR=\"*\"*}" || exit 0
concise=${cmdline##*DVR=\"} concise=${concise%%\"*}
device=${concise#* * * * } device=${device%% *}
if [[ $device =~ ^[A-Z]+= ]]
then
        tag=${device%%=*} tag=${tag,,}
        device=${device#*=}
        [ $tag = partuuid ] && device=${device,,}
        device="/dev/disk/by-$tag/$device"
fi
device=$(systemd-escape --path "$device").device
rundir=/run/systemd/system
echo > "$rundir/dmsetup-verity-root.service" "[Unit]
DefaultDependencies=no
After=$device
Before=dev-dm\x2d0.device
Requires=$device
[Service]
ExecStart=/usr/sbin/dmsetup create --concise \"$concise\"
RemainAfterExit=yes
Type=oneshot"
mkdir -p "$rundir/dev-dm\x2d0.device.requires"
ln -fst "$rundir/dev-dm\x2d0.device.requires" ../dmsetup-verity-root.service'
                $chmod 0755 "$buildroot$gendir/dmsetup-verity-root"
                echo >> "$buildroot/etc/dracut.conf.d/99-settings.conf" \
                    "install_optional_items+=\" $gendir/dmsetup-verity-root \""
        else
                local dropin=/usr/lib/systemd/system/dev-dm\\x2d0.device.requires
                $mkdir -p "$buildroot$dropin"
                $ln -fst "$buildroot$dropin" ../udev-workaround.service
                echo > "$buildroot${dropin%/*}/udev-workaround.service" '[Unit]
DefaultDependencies=no
After=systemd-udev-trigger.service
Before=dev-mapper-root.device
[Service]
ExecStart=/usr/bin/udevadm trigger
RemainAfterExit=yes
Type=oneshot'
                echo >> "$buildroot/etc/dracut.conf.d/99-settings.conf" \
                    'install_optional_items+="' \
                    "$dropin/udev-workaround.service" \
                    "${dropin%/*}/udev-workaround.service" \
                    '"'
        fi

        # Load overlayfs in the initrd in case modules aren't installed.
        if opt read_only
        then
                $mkdir -p "$buildroot/etc/modules-load.d"
                echo overlay > "$buildroot/etc/modules-load.d/overlay.conf"
                echo >> "$buildroot/etc/dracut.conf.d/99-settings.conf" \
                    'install_optional_items+=" /etc/modules-load.d/overlay.conf "'
        fi
fi

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        if test "x${options[release]}" = x31
        then $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFxq3QMBEADUhGfCfP1ijiggBuVbR/pBDSWMC3TWbfC8pt7fhZkYrilzfWUM
fTsikPymSriScONXP6DNyZ5r7tgrIVdVrJvRIqIFRO0mufp9HyfWKDO//Ctyp7OQ
zYw6NVthO/aWpyFfJpj6s4iZsYGqf9gByV8brBB8v8jEsCtVOj1BU3bMbLkMsRI9
+WiLjDYyvopqNBQuIe8ogxSxpYdbUz6+jxzfvhRoBzWdjITd//Gjd90kkrBOMWkO
LTqO133OD1WMT08G5NuQ4KhjYsVvSbBpfdkTcNuP8gBP9LxCQDc+e1eAhZ95g3qk
XLeKEK9j+F+wuG/OrEAxBsscCxXRUB38QH6CFe3UxGoSMnBi+jEhicudo+ItpFOy
7rPaYyRh4Pmu4QHcC83bNjp8NI6zTHrBmVuPqkxMn07GMAQav9ezBXj6umqTX4cU
dsJUavJrJ3u7rT0lhBdiGrQ9zPbL07u2Kn+OXPAC3dKSf7G8TvwNAdry9esGSpi3
8aa1myQYVZvAlsIBkbN3fb1wvDJE5czVhzwQ77V2t66jxeg0o9/2OZVH3CozD2Zj
v28LHuW/jnQHtsQ0fUyQYRmHxNEVkW10GGM7fQwxzpxFFS1O/2XEnfMu7yBHZsgL
SojfUct0FhLhEN/g/IINX9ZCVrzK5/De27CNjYE1cgYD/lTmQ0SyjfKVwwARAQAB
tDFGZWRvcmEgKDMxKSA8ZmVkb3JhLTMxLXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQI+BBMBAgAoAhsPBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAUCXGrkTQUJ
Es8P/QAKCRBQyzkLPDNZxBmDD/90IFwAfFcQq5ENl7/o2CYQ9k2adTHbV5RoIOWC
/o9I5/btn1y8WDhPOUNmsgbUqRqz6srlVplg+LkpIj67PVLDBwpVbCJC8o1fztd2
MryVqdvu562WVhUorII+iW7nfqD0yv55nH9b/JR1qloUa8LpeKw84JgvxF5wVfyR
id1WjI0DBk2taFR4xCfU5Tb262fbdFj5iB9xskP7oNeS29+SfDjlnybtlFoqr9UA
nY1uvhBPkGmj45SJkpfP+L+kGYXVaUd29M/q/Pt46X1KDvr6Z0l8bSUEk3zfcNdj
uEhtHBqSy1UPPAikGX1Q5wGdu7R7+mv/ARqfI6OC44ipoOMNK1Aiu6+slbPYphwX
ighSz9yYuG0EdWt7akfKR0R04Kuej4LXLWcxTR4l8XDzThYgPP0g+z0XQJrAkVhi
SrzICeC3K1GPSiUtNAxSTL+qWWgwvQyAPNoPV/OYmY+wUxUnKCZpEWPkL79lh6CM
bJx/zlrOMzRumSzaOnKW9AOliviH4Rj89OmDifBEsQ0CewdHN9ly6g4ZFJJGYXJ5
HTb5jdButTC3tDfvH8Z7dtXKdC4iqJCIxj698Xn8UjVefZQ2nbv5eXcZLfHtvbNB
TTv1vvBV4G7aiHKYRSj7HmxhLBZC8Y/nmFAemOoOYDpR5eUmPmSbFayoLfRsFXmC
HLs7cw==
=6hRW
-----END PGP PUBLIC KEY BLOCK-----
EOF
        else $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFturGcBEACv0xBo91V2n0uEC2vh69ywCiSyvUgN/AQH8EZpCVtM7NyjKgKm
bbY4G3R0M3ir1xXmvUDvK0493/qOiFrjkplvzXFTGpPTi0ypqGgxc5d0ohRA1M75
L+0AIlXoOgHQ358/c4uO8X0JAA1NYxCkAW1KSJgFJ3RjukrfqSHWthS1d4o8fhHy
KJKEnirE5hHqB50dafXrBfgZdaOs3C6ppRIePFe2o4vUEapMTCHFw0woQR8Ah4/R
n7Z9G9Ln+0Cinmy0nbIDiZJ+pgLAXCOWBfDUzcOjDGKvcpoZharA07c0q1/5ojzO
4F0Fh4g/BUmtrASwHfcIbjHyCSr1j/3Iz883iy07gJY5Yhiuaqmp0o0f9fgHkG53
2xCU1owmACqaIBNQMukvXRDtB2GJMuKa/asTZDP6R5re+iXs7+s9ohcRRAKGyAyc
YKIQKcaA+6M8T7/G+TPHZX6HJWqJJiYB+EC2ERblpvq9TPlLguEWcmvjbVc31nyq
SDoO3ncFWKFmVsbQPTbP+pKUmlLfJwtb5XqxNR5GEXSwVv4I7IqBmJz1MmRafnBZ
g0FJUtH668GnldO20XbnSVBr820F5SISMXVwCXDXEvGwwiB8Lt8PvqzXnGIFDAu3
DlQI5sxSqpPVWSyw08ppKT2Tpmy8adiBotLfaCFl2VTHwOae48X2dMPBvQARAQAB
tDFGZWRvcmEgKDMwKSA8ZmVkb3JhLTMwLXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQI4BBMBAgAiBQJbbqxnAhsPBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAAK
CRDvPBEfz8ZZudTnD/9170LL3nyTVUCFmBjT9wZ4gYnpwtKVPa/pKnxbbS+Bmmac
g9TrT9pZbqOHrNJLiZ3Zx1Hp+8uxr3Lo6kbYwImLhkOEDrf4aP17HfQ6VYFbQZI8
f79OFxWJ7si9+3gfzeh9UYFEqOQfzIjLWFyfnas0OnV/P+RMQ1Zr+vPRqO7AR2va
N9wg+Xl7157dhXPCGYnGMNSoxCbpRs0JNlzvJMuAea5nTTznRaJZtK/xKsqLn51D
K07k9MHVFXakOH8QtMCUglbwfTfIpO5YRq5imxlWbqsYWVQy1WGJFyW6hWC0+RcJ
Ox5zGtOfi4/dN+xJ+ibnbyvy/il7Qm+vyFhCYqIPyS5m2UVJUuao3eApE38k78/o
8aQOTnFQZ+U1Sw+6woFTxjqRQBXlQm2+7Bt3bqGATg4sXXWPbmwdL87Ic+mxn/ml
SMfQux/5k6iAu1kQhwkO2YJn9eII6HIPkW+2m5N1JsUyJQe4cbtZE5Yh3TRA0dm7
+zoBRfCXkOW4krchbgww/ptVmzMMP7GINJdROrJnsGl5FVeid9qHzV7aZycWSma7
CxBYB1J8HCbty5NjtD6XMYRrMLxXugvX6Q4NPPH+2NKjzX4SIDejS6JjgrP3KA3O
pMuo7ZHMfveBngv8yP+ZD/1sS6l+dfExvdaJdOdgFCnp4p3gPbw5+Lv70HrMjA==
=BfZ/
-----END PGP PUBLIC KEY BLOCK-----
EOF
        fi
        $gpg --verify "$1"
        test x$($sed -n '/=/{s/.* //p;q;}' "$1") = x$($sha256sum "$2" | $sed -n '1s/ .*//p')
}

# OPTIONAL (BUILDROOT)

function enable_rpmfusion() {
        local key="RPM-GPG-KEY-rpmfusion-free-fedora-${options[release]}"
        local url="https://download1.rpmfusion.org/free/fedora/releases/${options[release]}/Everything/$DEFAULT_ARCH/os/Packages/r/rpmfusion-free-release-${options[release]}-1.noarch.rpm"
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
if test "x${options[release]}" = x31
then rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFvEZi0BEADeq0E2/aYDWMYnUBloxAamr/DBo21/Xida69lQg/C8wGB/jz+i
J9ZDEnLRDGlotBl3lwOhbzwXxk+4azH77+JIuUDiPkBb6e7rld0EMWNykLuWifV0
Eq7qVBtr1cQfvLMDySvzIBPEGy3IbFnr7H7diR+A0WiwltVLcv4wW/ESRZUChBxy
TGgQrYk98TGiJGMWlwi7IzopOliAYrc7oM1XyZQlTffhS5b0ygiwIxGOOjVR3waB
m//0PVj8hZ+kHBgn2hXnLlWBkCRosxHmg+xcosUBgfBqKBPN8M800F6svvZS1msN
mef7y2QytA9LSpey6mznqKEY8x8+9Ub4FCGiEEw8SoDCU48NpmADr6PXoJAtihEi
4NuBiqzpabKDR7IfhEWNgVM840OCmizFyT9L++SDZmww8rUHx55VOzVEf4fSRPXY
gduexRo377+bj+wdpKfrUddkbdxuDVWweq8k5fZz7Y7HYtM60j9WxtUoLF37MNgZ
5bwrOU2NhLP+aqwyeE86/BqDdKVzxeq+PAaIl1ujTqbmJYJO0Kmt4G+GPhj6TpTq
+X+Ci+YskPEcp7dqpH38rpuA3ZAVH4tHkW9UFFBHrvnxuOLrrAflondgLTo1xNo6
E8Qrq7PGCjq/FdVM9tC3hupeKuXz5jaf65qbln4COromTXm5KyNOlWVgMwARAQAB
tFNSUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMSkgPHJw
bWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgALxYh
BFmn/gf2ZMGydofF0m3u8FHEgZN6BQJbxGYtAhsDBAsJCAcDFQgKAh4BAheAAAoJ
EG3u8FHEgZN6E5EQAN5kzvCyT/Ev6H/rS4QQE6+Zxb9YCGnlUOwPXcwtAqjGl4Hn
kt9LXnrd4DThLBLEGZUpBe5/oNuZOLWRWvTG7UHR+pBdtxIyqUlxBhiIwSe+Q7rZ
gehiXl2PhnaBHyTLoFGczNWiqKSIORnSmVg4SXuteG4So0PzRWBD9r2/7P/mZGyd
wyiH34YUzsedPOO1sER8o+tQ6C9RlRmhZRQ9hBJIymga1FfCms6X5lEFfbsuSjEt
acLvLJuO7bxfoYPiC2l+psFAitgT7UeEm/KW/Ul2M2YVONu1pRCkEoJzJ4B1ki9/
MK6Kw9QyQ6KXmOmzckJaInZQrwtcffjsdCjdQgoPUA//PVsysM4dtE7TPx2iRC2S
Vci0eGT+XV3tUlDDlMLfx6PhpfAddN3okGIWE0Nwc9yNwwn+R2H/Nrw0Q74qiwP7
uCgzGQBEKOATwJdm/EbtzSOzTgeunrlb1HO+XgjE+VBxp9vdzS/sOecixPyGdjW3
B1NIHAU1O9tgQcBNSJ4txKEnKHw92HViHLXpOVIIeXW+2bjtgTtTE3TfAYVnyLMn
uplg21hoH2L+fC281fgV64CzR+QjOiKWJSvub6wzy1a7/xPce8yaE89SwmxxVroS
Ia81vrdksRmtLwAhgJfh6YoSdxKWdtB+/hz2QwK+lHV368XzdeAuWQQGpX3T
=NNM4
-----END PGP PUBLIC KEY BLOCK-----
EOG
else rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFrUUycBEADfDoQDUWJBi2QpXmFf7be+DMqBjgSZp3ibe29ON1iLe+gfyFjC
0KCuuz+RdfRizKkovlqMC7ucWqDIkc3fCsoWpb+Hpfw51WvLQCyodB0suHfaY0Rk
k8Jhg5u0qnL8lJfiFEiVesKoUziIf+phLKpITK2LBD0kBNn5OnkWrPwNuN0wyvXP
HAqxz3KZxxwBEn1RwUhYIJCZStaFoTDziWHIB2cYIKSdfquOh1UCVuQj63WnUXNL
e4Wqbc62xJQBZkCfs3+r4FybcGrB07Mju0i7MeWzH6dMHYx6ZkGyA5CmOYfoRV2o
CfOHqm3e+MvHDN+7JF6epNSQyMX47KIA5foJZlMe0RhuO8SwHCMc6d/Zc7iFKmG1
IsWdBzGvJkMv1g4OaEAYRuVO5jWWO4370UVqQ9kvzky3aqGI391wekSSqDbLer6a
8isf4QDEqjzhVswxXg99I4zkXlMcYkBRumGBtq1KkcAtLoobVEg1WbQbQQTu4j/H
ZKgFadwhasJK1jN+PtW+erV0l1KyDzjR4vTRR9AWg9ahsTLtRe9HvkBLBhKtrhW0
oPqOW5I3n0LChnegYy7jit5ZPGS7oZvzbu+zok+lwQFLZdPxM2VuY6DQE8BNdXEP
3nLNGbVubv/MZILOws8/ACiONeW9C+RvzYznwmM+JqqhqmKiyr8WWlBfAQARAQAB
tFNSUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMCkgPHJw
bWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgALxYh
BIDDssbnJ/PgkrRz4D3yzkPArtpuBQJa1FMnAhsDBAsJCAcDFQgKAh4BAheAAAoJ
ED3yzkPArtpusgsP/RmuZOKEgrGL12uWo9OEyZLTjjJ9chJRPDNXPQe7/atNJmWe
WwkWbKcWwSivwGP04SsJF1iWRcSwCOLe5wBSpuM5E1XsDufzKsLH1WkjOtDQ+O8U
kkJwV64WT06FkSUze+cS7ni5LSObVqPvBtbKFl8lWciG1IDlK5++XW2VLD3dghAW
5boFZjoVNZoYhlyeZmtcDVlFdXex5Sw0B/gJY4uaHXBXrA1YyE4vBlrSDYrfh4eU
glSGNMNS++78bQsN/C3VmtXpWsvNJa4jxYaXFOJd5g3iX5ttDQYF46PgJckZVurA
8PT066i4eJOwqDPnOQncsudcpbLPt+0F3cyeDPtjKh+RY48hAhTW0/lDq2onhGPk
SOTDhPrx6vWLqDNBKOio3VloFdEOCsm2OniGZojJADm6m6kErY6n3On3y9TE2GDm
Bx8apPxN7FJvwFqvieZt6B1R+57VStQ0YBCsfC1i5EVsNPnyoNqwvxs2IGsn3P/+
SuCw9+qa5aRsF+jdnHxKMmj1xm8dVtCCLfaMb4cl7wxgq9zolvlbRFnfHfhRoKhp
fs3khghy5i2AU/bOChxRngX2QWR1A117IeADWtuspMFEOyeU5BlMcqjkFdOZI3jX
0VmGnXLcUEIa89z/0ktU6TW3MLQ/laFqj5LhGR9jzaDL6S7pOzNqQT4p3jzJ
=S0gf
-----END PGP PUBLIC KEY BLOCK-----
EOG
fi
curl -L "$url" > rpmfusion-free.rpm
curl -L "${url/-release-/-release-tainted-}" > rpmfusion-free-tainted.rpm
rpm --checksig rpmfusion-free{,-tainted}.rpm
rpm --install rpmfusion-free{,-tainted}.rpm
exec rm -f rpmfusion-free{,-tainted}.rpm
EOF
        test "x$*" = x+nonfree || return 0
        key=${key//free/nonfree}
        url=${url//free/nonfree}
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
if test "x${options[release]}" = x31
then rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFvEZjsBEADo+8aA0e20azf2vU4JJ2rVHnr9RpVUcRYmr/rFEsEeYMIvDAYz
ssprKuuz89XTe5OR8RSrTIVFOTqYrZYxuQbR35rzr9wpk45szcUMDNzi0L83AemS
v1JgBF2gSoF9Ajbhbdwxxqje+yn86u0xWWsG4Xu1N/KZE/oyqAYwWzH9nizrSRSv
SCsjZMk4SwEPB0lp2zTf21k5YwIv05+ubHq5/h9WScjjoA4LCJHIikNptONFemhS
Ys3Vsacd0g4mAx3AyU8gGaFkQXapwhQWi1/UCbqFT/3S1ZApYthdYBpFwSv7PgUa
BBJGFzwxrch9NF1wHivO4uzmPK2V8REKt2EgwPUfaAYCabPxxFFsWNOimv1zz3Wb
2DPZfE1YDjAi4qNfXENkqSReys7ETi2fGw2pr6PQtLJFYLbpKwXVvdr0PuAPPNQo
kCAuCZKnNitxsxyaGYxN2gq3D6excKpo+3JQAdRTdC+vAFACs41QDLCLBYQUL4zn
eXR/hkSmyeEDyrkuRztqUxI0eobMOS6KI6c2u+tYhWQY1OH1piV1aOa4OQQKFdZH
6WQAnbMqafG4lPmEO5cDT4JNRzWfyZXXa750mq6X3r2iRZMlroHoJAMUmF6+r8vP
AfjC3Haqfbp6HlNpTET8GU8eeeNQM33Qpq1H2tGJPIt3ZVHOTzjjMnvFdwARAQAB
tFZSUE0gRnVzaW9uIG5vbmZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMSkg
PHJwbWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgA
LxYhBEyrlRp0k9ksrewEIZzmOgNUqGCSBQJbxGY7AhsDBAsJCAcDFQgKAh4BAheA
AAoJEJzmOgNUqGCSkzwP/35oDsqFQNZGT2PJ3BpLkK/e8INCRsBgUHHzQiGri69v
OBDt6RoJwKEYfsx7ps0oRhci6NZ5aTJL4g25xBibWB9dvce4c25Kho7VHassxXzv
j6MrAuFNFHWpNNGXgiBTfMBOqcLxfx550wJyzyUVxxsmjbRm8Irz/ijZXavzyTw5
xNmZw6a2XH1Zx9bNdv+o5I5pkmdJJGSw6BbI7j5xysV+A5yIFtCnKCwhsXrGRjnR
9V8MuocAXjzayLWJ4E0daZkJlyR5mhYuae4PR1wt75qj8UesjWTAniQFlWMe52+G
Iqukb6TvxrLLTdaFi8orpoDG5PsdQ2kfyRQDcK5UMM4X8BC59Bq0NtuIezMio40O
1wGZFf1tUdGCImf5JtboKRTeAp32uvPjYR1Bbya8Yup6OuCrKDrdOdqKlULFp3H+
ia8W8hFCaGgvnpNveoBLFcMq6xxorQ4LhEcwnLABs9Y8UnL5Ao2ozijVA7Pkhdep
dt5CYmEq77bxpQT1tLUt9jp246gZgMQQDZAR6BW+fg3FCpXDWguxF+Xzuf7JuL9O
V2SKYTbdiljladNZO0sq566U6GJptKhl8pHlihkNyHc6jkQGxnzpzFolTUl66jbc
f9jO+f+R9C+FDT1fcPPIolYTBRCvYQ9B6c+olHVTNNYUmW36TThsbXiYeqQw4JPA
=Wn2x
-----END PGP PUBLIC KEY BLOCK-----
EOG
else rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFrUUy4BEAC0TX9UViv0ZWUMruCuR3s8niI388HlqPBF4eKv30V+zlwFiw/6
JfrWlOZ1QfcK5DJbQT3LMVsVyGU3KTCquHGTPusSPFVpG1KLhBwXGMdZ3/y14xGZ
xI37PyaZ5T170NchcST14f7cjkLtBuJ3IOIMwv1Uxi5Oc8QOo/i3RHMiiE1JKGuA
FR8Td77VioV9+gr41VlexdjeAvf0UGylstbLkiEqYig2xhbD49vGZ97V/PJXEbpd
nb6nJz0SUIKczQYbln7Arm9/8H91dBgWFkp8URVxtdQn/GJ3D6DBs+t6PlS1QD5m
2k999hDy0iRduwc4t2mO5jUio7LeMi0zkCtvx4HzJXSYissx7uR3odi32N5Z3Ywd
ZnmdqCDVXx7QXSQ0V6UIffPHB+JzFT4EfIENCp55puzMXJZkugaP8PX3VtbPsCz6
WMddNs7674VrJR7uhtmpumfNo9taXJdesZbcuUs6DyoW24WBEVDjlhPDjKCID0bm
0uPWheyxt3I4kTcTaRWJfQN8rQYHFtRpIE9qCDRNCsdYoMjuGHIlcBPTcNn3ksfv
Hwrr7rYpKPHp/lkhoneWXhnBWNd6r5/1zy7bHxiSPgbPZt2YB5jAE3jHRmVyHCQo
J6/+OcRhbL2cKUOBvuwQQXe/7qPPSjnkCamiQoiSZGOL39f8ql/rKJg98wARAQAB
tFZSUE0gRnVzaW9uIG5vbmZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMCkg
PHJwbWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgA
LxYhBIAXHI0syKq4TIRI6b3W7MQdFKeVBQJa1FMuAhsDBAsJCAcDFQgKAh4BAheA
AAoJEL3W7MQdFKeVjK8QAIjV7blJJbCShlCpU1ul5wcDYMuF6nw+DmaPuL1koAYF
dYRP+o9Sho/7tjkLT6lQaePSPF/SBxUjgI3+0HLb3soTwwSMfkCxF3DXlO9hUjJr
L1jIUubx2RpBhjWpwpdJ/2JZHb2fwlKnKfS0bjyypV6QOngbspyXi/FKyGYF1UQO
WZG0fuOr/vu1+VUY2YN8qnCkuyCnpTy5VbfWOht98nfnCf3vo+FXoMWx7wKB+CoY
M9FryDlyF5te/z5dsv7/8MiSavw5vpdDdzqaiN7j69m4nHYRYco9pj3oM2WN/iu8
4Quf2Zfa4YgdXO1oYn7GYCmJZftnvEBWVZ1DjgGvoa1FV/suvDlc6+x0g6M2bORX
jlnG1cjDD8eKjhy2HvVQLbnJxGce4wwvCHppgs6lHowIMNfgPvKFi1Lt2ABw0ojR
wjYELGwF60s2u0Doh0Um3SNsFWGF4jcSyq/5+fdk93qPqEGv44tjrbRtC3O5KNCZ
YTLbiR0ZcubpQap7pZHJLSbjPh74HrsgXtNNpnDNCQOQecSIuiff5fZzN7tyJrLL
NCfJC5FlD/HHbNLLBYBOCM6N7h3gcyAJBGp6JwpchbZf5kOFMWlZIr8J8TDv2EHC
shobGp/ukk6OFzG9MOnPFn19tnO1ZMB+ewATd968K+3yEwJ2woX02iguq77LGPj4
=Gzco
-----END PGP PUBLIC KEY BLOCK-----
EOG
fi
curl -L "$url" > rpmfusion-nonfree.rpm
curl -L "${url/-release-/-release-tainted-}" > rpmfusion-nonfree-tainted.rpm
rpm --checksig rpmfusion-nonfree{,-tainted}.rpm
rpm --install rpmfusion-nonfree{,-tainted}.rpm
exec rm -f rpmfusion-nonfree{,-tainted}.rpm
EOF
}

# OPTIONAL (IMAGE)

function save_rpm_db() {
        opt selinux && echo /usr/lib/rpm-db /var/lib/rpm >> root/etc/selinux/targeted/contexts/files/file_contexts.subs
        mv root/var/lib/rpm root/usr/lib/rpm-db
        echo > root/usr/lib/tmpfiles.d/rpm-db.conf \
            'L /var/lib/rpm - - - - ../../usr/lib/rpm-db'
}

function drop_package() while read -rs
do exclude_paths+=("${REPLY#/}")
done < <(rpm --root="$PWD/root" -qal "$@")
