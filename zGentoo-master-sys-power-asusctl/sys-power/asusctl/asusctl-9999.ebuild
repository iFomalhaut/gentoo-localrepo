# Copyright 1999-2021 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
EAPI=7

#### IMPORTANT ####
# This ebuild is mostly unmaintained - DO NOT USE IT!

inherit systemd cargo git-r3 linux-info xdg

_PN="asusd"

DESCRIPTION="${PN} (${_PN}) is a utility for Linux to control many aspects of various ASUS laptops."
HOMEPAGE="https://asus-linux.org"
EGIT_REPO_URI="https://gitlab.com/asus-linux/${PN}.git"

LICENSE="MPL-2.0"
SLOT="9999"
IUSE="+acpi +gfx gnome notify"
REQUIRED_USE="gnome? ( gfx )"

RDEPEND="!!sys-power/rog-core
    !!sys-power/asus-nb-ctrl
    !!sys-power/suppergfxctl
    !<=sys-power/asusctl-9999
    acpi? ( sys-power/acpi_call )
    gnome? (
        x11-apps/xrandr
        gnome-base/gdm
        gnome-extra/gnome-shell-extension-asusctl-gex:3
    )"
DEPEND="${RDEPEND}
	>=virtual/rust-1.44.0
    >=sys-devel/llvm-9.0.1
    >=sys-devel/clang-runtime-9.0.1
    dev-libs/libusb:1
    gfx? ( !sys-kernel/gentoo-g14-next )
    sys-apps/systemd:0=
	sys-apps/dbus
"

src_unpack() {
    default
    git-r3_src_unpack
    cargo_live_src_unpack
}

src_prepare() {
    require_configured_kernel

    # make sure acpi_call is disabled (causes massive problems on gentoo)
    linux_chkconfig_present ACPI_CALL && die "CONFIG_ACPI_CALL must be disabled."

    # checking for needed kernel-modules since v3.2.0
    k_wrn_vfio="\n"
    linux_chkconfig_module VFIO_PCI || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO_PCI should be enabled as module\n"
    linux_chkconfig_module VFIO_IOMMU_TYPE1 || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO_IOMMU_TYPE1 should be enabled as module\n"
    linux_chkconfig_module VFIO_VIRQFD || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO_VIRQFD should be enabled as module\n"
    linux_chkconfig_module VFIO_MDEV || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO_MDEV should be enabled as module\n"
    linux_chkconfig_module VFIO || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO should be enabled as module\n"
    [[ ${k_wrn_vfio} != "\n" ]] && ewarn "\nKernel configuration mismatch (needed for switching gfx):\n${k_wrn_vfio}"

    # checking for touchpad dependencies
    k_wrn_touch="\n"
    linux_chkconfig_present PINCTRL_AMD || k_wrn_touch="${k_wrn_touch}CONFIG_PINCTRL_AMD not found, should be either builtin or build as module\n"
    linux_chkconfig_present I2C_HID || k_wrn_touch="${k_wrn_touch}CONFIG_I2C_HID not found, should be either builtin or build as module\n"
    [[ ${k_wrn_touch} != "\n" ]] && ewarn "\nKernel configuration mismatch (needed for touchpad support):\n${k_wrn_touch}"

    # fix nvidia as primary (might be gentoo specific)
    sed -i 's/Section\ /Section\ "Module"\n\tLoad\ "modesetting"\nEndSection\n\nSection\ /g' \
        ${S}/daemon/src/ctrl_gfx/mod.rs || die "Can't add modesetting to the gfx switcher."

    sed -i '/Option\ "PrimaryGPU"\ "true"/c\EndSection\n\nSection\ "Device"\n\tIdentifier\ "nvidia"\n\tDriver\ "nvidia"\n\tOption\ "AllowEmptyInitialConfiguration"\ "true"\n\tOption\ "PrimaryGPU"\ "true""#;' \
        ${S}/daemon/src/ctrl_gfx/mod.rs || die "Can't add nvidia device section to the gfx switcher."
    
    default
}

src_compile() {
    cargo_gen_config
    ## patch config to NOT trigger install in "all" target (this will fail)
    sed -i 's/build\ install/build/g' Makefile
    default
}

src_install() {
    insinto /etc/${_PN}
    doins data/${_PN}-ledmodes.toml
    doins "${FILESDIR}"/${_PN}.conf && ewarn Resetted /etc/${_PN}/${_PN}.conf make sure to check your settings!

    insinto /usr/share/icons/hicolor/512x512/apps/
    doins data/icons/*.png

    insinto /etc/udev/rules.d/
    doins data/${_PN}.rules

    insinto /usr/share/dbus-1/system.d/
    doins data/${_PN}.conf

    if [ -f data/_asusctl ] && [ -d /usr/share/zsh/site-functions ]; then
        insinto /usr/share/zsh/site-functions
        doins data/_asusctl
    fi
    
    ## GFX
    if use gfx; then
        ## mod blacklisting
        insinto /etc/modprobe.d
        doins ${FILESDIR}/90-nvidia-blacklist.conf

        # xrandr settings for nvidia-primary (gnome only, will autofail on non-nvidia as primary)
        if use gnome; then
            insinto /etc/xdg/autostart
            doins "${FILESDIR}"/xrandr-nvidia.desktop

            insinto /usr/share/gdm/greeter/autostart
            doins "${FILESDIR}"/xrandr-nvidia.desktop
        else
            ewarn "you're not using gnome, please make sure to run the following, when logging into your WM/DM: \n \
\`xrandr --setprovideroutputsource modesetting NVIDIA-0\; xrandr --auto\`\n \
Possible locations are ~/.xinitrc, /etc/sddm/Xsetup, etc.\n"
        fi
    fi

    insinto /usr/share/dbus-1/system.d/
    doins data/${_PN}.conf

    systemd_dounit data/${_PN}.service
    systemd_douserunit data/${_PN}-user.service
    use notify && systemd_douserunit data/asus-notify.service

    use notify && cargo_src_install --path "asus-notify"
    cargo_src_install --path "asusctl"
    cargo_src_install --path "daemon"
}

pkg_postinst() {
    xdg_icon_cache_update
    ewarn "Don't forget to reload dbus to enable \"${_PN}\" service, \
by runnning:\n \`systemctl daemon-reload && systemctl reload dbus &&  \
udevadm control --reload-rules && udevadm trigger\`\n"

    x11_warn_conf=""
    for c in `grep -il nvidia /etc/X11/xorg.conf.d/*.*`; do 
        if ! `grep -q asusd "$c"` && [[ "$c" != *"90-asusd-nvidia-pm.rules" ]]; then
            x11_warn_conf="$x11_warn_conf$c\n";
        fi
    done
    [[ "$x11_warn_conf" == "" ]] || ewarn "WARNING: Potential inteferring files found:\n$x11_warn_conf"
}

pkg_postrm() {
    xdg_icon_cache_update
}
