# GNU/Linux Distro Installer

This is a collection of shell functions to build secure Linux-based operating system images.  I am writing this project in an attempt to automate and unify a lot of the things I would do manually when installing systems, as well as to cross-compile images from fast modern hardware tuned for old embedded chips and uncommon CPU architectures.

## About

The primary goal here is interchangeable immutable disk images that are verified by verity, which is itself verified by the kernel's Secure Boot signature on UEFI platforms.  This script creates a container to run the build procedure which outputs components of an installed operating system (such as the root file system image, kernel, initrd, etc.) that can be assembled as desired, but my testing focuses on three main use cases:

 1. A system's bootable hard drive is GPT-partitioned with an ESP, several (maybe three to five) partitions of five or ten gigabytes reserved to store root file system images, and the rest of the disk used as an encrypted `/var` partition for persistent storage.  A signed UEFI executable corresponding to each active root file system partition is written to the ESP so that each image can be booted interchangeably with zero configuration.  This allows easily installing updated images or migrating to different software.

    Example installation: `bash -x install.sh -VZE /boot/EFI/BOOT/BOOTX64.EFI -IP e08ede5f-56d4-4d6d-b8d9-abf7ef5be608 workstation.sh`

 2. The installer produces a single UEFI executable that has the entire root file system image bundled into it.  Such a file can be booted on any machine from a USB key, via PXE, or just from a regular hard drive's ESP as a rescue system.

    Example installation: `bash -x install.sh -KSE /boot/EFI/BOOT/RESCUE.EFI -a admin::wheel -p 'cryptsetup dosfstools e2fsprogs kbd kernel-modules-extra lvm2 man-db man-pages sudo vim-minimal'`

 3. All boot-related functionality is omitted, so a file system image is created that can be used as a container.

    Example installation: `bash -x install.sh -S app.sh`

The installer can produce an executable disk image for testing each of these configurations if a command to launch a container or virtual machine is specified.

## Usage

The `install.sh` file is the entry point.  Run it with `bash install.sh -h` to see its full help text.  Since it performs operations such as starting containers and overwriting partitions, it must be run as root.

The command should usually be given at least one argument: a shell file defining settings for the installation.  There are a few such example files under the `examples` directory.  The file should at least append to the associative array named `options` to define required settings that will override command-line options.  It should append to the `packages` array as well to specify what gets installed into the image.  The installed image can be modified by defining a function `customize` which will run in the build container with the image mounted at `/wd/root`.  For more complex modifications, append to the array `packages_buildroot` to install additional packages into the container, and define a function `customize_buildroot` which runs on the host system after creating the container at `$buildroot`.

The resulting installation artifacts are written to a unique output directory in the current path.  For example, `vmlinuz` (or `vmlinux` on some platforms) is the kernel and `final.img` is the root file system image (containing verity signatures if enabled) that should be written directly to a partition.  If the `uefi` option was enabled, `BOOTX64.EFI` is the UEFI executable (signed for Secure Boot if a certificate and key were given).  If the `executable` option was enabled, `disk.exe` is a disk image that can also be executed as a program.

For a quick demonstration, it can technically be run with no options.  In this case, it will produce a Fedora image containing `bash` that can be run in a container.

    bash -x install.sh
    systemd-nspawn -i output.*/final.img

For a bootable system example with no configuration file, use `-S` to compress the root file system, `-K` to bundle it in the initrd, `-Z` to protect it with SELinux, and `-E` to save it to your EFI system partition.  If optional PEM certificate and key files were given, the executable will be signed with them.  It can then be booted with the UEFI shell or by running `chainloader` in GRUB.

    bash -x install.sh -KSZE /boot/efi/EFI/BOOT/DEMO.EFI -c cert.pem -k key.pem

Some other options are available to modify image settings for testing, such as `-d` to pick a distro, `-p` to add packages, and `-a` to add a user account with no password for access to the system.

    bash -x install.sh -KSVZ -d centos -p 'kbd man-db passwd sudo vim-minimal' -a user::wheel

## License

The majority of the code in this repository is just writing configuration files, which I do not believe to be covered by copyright.  Any nontrivial components of this repository should be considered to be under the GNU GPL version 3 or later.  The license text is in the `COPYING` file.

## Status / Notes / To Do

The project may be completely revised at some point, so don't expect anything in here to be stable.  Some operations might still require running on x86_64 for the build system.  Three distros are supported to varying degrees:

  - Fedora supports all features, but only Fedora 30 and 31 (the default) can be used.
  - CentOS 8 should support everything.  CentOS 7 systemd is too old to support building a UEFI image and persistently tracking the `/etc` overlay with Git.
  - Gentoo supports all features in theory, but its SELinux policy is unsupported with systemd upstream, so it is only running in permissive mode.

### General

**Support configuring systemd with the etc Git overlay.**  The `/etc` directory contains the read-only default configuration files with a writable overlay, and if Git is installed, the modified files in the overlay are tracked in a repository.  The repository database is saved in `/var` so the changes can be stored persistently.  At the moment, the Git overlay is mounted by a systemd unit in the root file system, which happens too late to configure systemd behavior.  It needs to be set up by an initrd before pivoting to the real root file system.

**Implement content whitelisting.**  (There is a prototype in *TheBindingOfIsaac.sh*.)  The images currently include all installed files with an option to blacklist paths using an exclude list.  The opposite should be supported for minimal systems, where individual files, directories, entire packages, and ELF binaries (as a shortcut for all linked libraries) can be listed for inclusion and everything else is dropped.

**Maybe add a disk formatter or build a GRUB image.**  I have yet to decide if the pieces beneath the distro images should be outside the scope of this project, since they might not be worth automating.  There are two parts to consider.  First, whether to format a disk with an ESP, root partition slots, and an encrypted `/var` partition.  Second, whether to configure, build, and sign a GRUB UEFI executable to be written to an ESP as the default entry.  I also have two use cases to handle with GRUB.  In the case of a formatted disk with root partitions, it needs to have a menu allowing booting into any of the installed root partitions, but it should default to the most recently updated partition unless overridden.  In the case where I'd fill a USB drive with just an ESP and populate it with images containing bundled root file systems, GRUB needs to detect which machine booted it via SMBIOS and automatically chainload an appropriate OS for that system.

**Use the list of excluded paths in ext4.**  Only squashfs is dropping the files.

**Extend the package finalization function to cover all of the awful desktop caches.**  Right now, it's only handling glib schemas to make GNOME tolerable, but every other GTK library and XDG specification has its own cache database that technically needs to be regenerated to cover any last system modifications.  To make this thoroughly unbearable, none of these caching applications supports a target root directory, so they all will need to be installed in the final image to update the databases.  I will most likely end up having a dropin directory for package finalization files when this gets even uglier.

### Fedora

**Report when the image should be updated.**  When a system saves the RPM database and has network access, it should automatically check Fedora updates for enhancements, bug fixes, and security issues so it can create a report advising when an updated immutable image should be created and applied.  I will probably implement this in a custom package in my local repo and integrate it with a real monitoring server, but I am noting it here in case I decide to add it to the base system and put a report in root's MOTD (to provide the information without assumptions about network monitoring).  The equivalent can be done for CentOS or via GLSAs, but Fedora is my priority here.

### CentOS

There is nothing planned to change here at this point.  CentOS must be perfect.  All known shortcomings in the generated images are due to the status of the distro (e.g. CentOS 7 is too old to have a UEFI stub), so they will not be fixed by this script.

### Gentoo

**Implement optional file filtering functions based on categories like debugging or development.**  Packages such as GCC should be filtered to install runtime components like `libstdc++` but not compilers and headers for systems that won't do development.  This could probably be implemented for all distros, but it will only be useful in Gentoo since Fedora et al. use subpackages for that functionality which can just be omitted.

**Maybe support using a specific commit for the repository.**  Since Gentoo's repository is maintained in a rolling-release style, there should be a way to specify a snapshot to get the same ebuild revisions.

### Example Systems

**Prepopulate a Wine prefix for the game containers.**  I need to figure out what Wine needs so it can initialize itself in a chroot instead of a full container.  The games currently generate the Wine prefix (and its `C:` drive) every run as a workaround.  By installing a prebuilt `C:` drive and Wine prefix with the GOG registry changes applied, runtime memory will be reduced by potentially hundreds of megabytes and startup times will improve by several seconds.

**Maybe support the proprietary NVIDIA driver with an option in the game containers.**  The proprietary driver apparently doesn't implement any of the interfaces used by everything else, so systems unfortunate enough to not have Nouveau support are unable to run the games included here.  An option could be added to bind the NVIDIA devices and install the libraries from RPM Fusion to use them, but it's probably not worth making all of the examples uglier to support proprietary nonsense.

**Provide servers.**  The only bootable system examples right now are simple standalone workstations.  I should try to generalize some of my server configurations, or set up a network workstation example with LDAP/Kerberos/NFS integration.  Also, something should demonstrate persistent encrypted storage, which servers are going to require.  (Just add one line to `/etc/crypttab` and `/etc/fstab` to mount `/var`.)

**Add cross-compiling examples.**  I've been using the build system on x86_64 to create images for a handful of weird architectures for a few weeks now, so those configurations should be cleaned and added to the example systems.  Until then, all you need to do is set the `arch` option when using Gentoo, and everything magically works (at least for the targets I have).  Of course, tune your portage profile and kernel config for the specific target system for best results.
