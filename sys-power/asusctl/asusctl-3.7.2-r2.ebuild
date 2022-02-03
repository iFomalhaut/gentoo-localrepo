# Copyright 1999-2021 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
EAPI=7

inherit systemd cargo git-r3 linux-info xdg

_PN="asusd"

DESCRIPTION="${PN} (${_PN}) is a utility for Linux to control many aspects of various ASUS laptops."
HOMEPAGE="https://asus-linux.org"
SRC_HASH="08341a60dec85e75817bb03a91ee8d3a"
SRC_URI="
    https://gitlab.com/asus-linux/${PN}/-/archive/${PV}/${PN}-${PV}.tar.gz
    https://vendors.retarded.farm/${PN}/vendor-${PV}.tar.xz -> vendor_${PN}-${PV}.tar.xz
"

LICENSE="MPL-2.0"
SLOT="0/3"
KEYWORDS="~amd64"
IUSE="+acpi +gfx gnome notify"
REQUIRED_USE="gnome? ( gfx )"


RDEPEND="!!sys-power/rog-core
    !!sys-power/asus-nb-ctrl
    !!sys-power/supergfxctl
    acpi? ( sys-power/acpi_call )
    gnome? (
        x11-apps/xrandr
        gnome-base/gdm
    )
    "
DEPEND="${RDEPEND}
    >=virtual/rust-1.51.0
    >=sys-devel/llvm-10.0.1
    >=sys-devel/clang-runtime-10.0.1
    dev-libs/libusb:1
    gfx? ( !sys-kernel/gentoo-g14-next )
    gnome? ( gnome-extra/gnome-shell-extension-asusctl-gex:0/3 )
    sys-apps/systemd:0=
	sys-apps/dbus
"

S="${WORKDIR}/${PN}-${PV}"

src_unpack() {
    unpack ${PN}-${PV}.tar.gz
    # adding vendor-package
    cd ${S} && unpack vendor_${PN}-${PV}.tar.xz
}

src_prepare() {
    require_configured_kernel

    # checking for needed kernel-modules since v3.2.0
    k_wrn_vfio=""
    linux_chkconfig_module VFIO || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO should be enabled as module\n"
    linux_chkconfig_module VFIO_IOMMU_TYPE1 || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO_IOMMU_TYPE1 should be enabled as module\n"
    linux_chkconfig_module VFIO_MDEV || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO_MDEV should be enabled as module\n"
    linux_chkconfig_module VFIO_PCI || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO_PCI should be enabled as module\n"
    linux_chkconfig_module VFIO_VIRQFD || k_wrn_vfio="${k_wrn_vfio}CONFIG_VFIO_VIRQFD should be enabled as module\n"
    if [[ ${k_wrn_vfio} != "" ]]; then 
        ewarn "\nKernel configuration issue(s), needed for switching gfx vfio mode (disabled by default):\n${k_wrn_vfio}"
    else
        ## enabeling fvio mode
        einfo "Kernel configuration matches FVIO requirements. (enabeling now vfio gfx switch by default)"
        sed -i 's/gfx_vfio_enable:\ false,/gfx_vfio_enable:\ true,/g' ${S}/daemon/src/config.rs || die "Could not enable VFIO."
    fi

    # checking for touchpad dependencies
    k_wrn_touch=""
    linux_chkconfig_present I2C_HID_CORE || k_wrn_touch="${k_wrn_touch}CONFIG_I2C_HID_CORE not found, should be either builtin or build as module\n"
    linux_chkconfig_present I2C_HID_ACPI || k_wrn_touch="${k_wrn_touch}CONFIG_I2C_HID_ACPI not found, should be either builtin or build as module\n"
    linux_chkconfig_present HID_ASUS || k_wrn_touch="${k_wrn_touch}CONFIG_HID_ASUS not found, should be either builtin or build as module\n"
    linux_chkconfig_present PINCTRL_AMD || k_wrn_touch="${k_wrn_touch}CONFIG_PINCTRL_AMD not found, should be either builtin or build as module\n"
    [[ ${k_wrn_touch} != "" ]] && ewarn "\nKernel configuration issue(s), needed for touchpad support:\n${k_wrn_touch}"

    # fix nvidia as primary (might be gentoo specific)
    # this enables modesetting modules and nvidia as a device entry in the generated 90-nvidia-primary.conf (if siwtched to nvidia as primary)
    sed -i '/Option\ "PrimaryGPU"\ "true"/c\EndSection\n\nSection\ "Module"\n\tLoad\ "modesetting"\nEndSection\n\nSection\ "Device"\n\tIdentifier\ "nvidia"\n\tDriver\ "nvidia"\n\tOption\ "AllowEmptyInitialConfiguration"\ "true"\n\tOption\ "PrimaryGPU"\ "true""#;' \
        ${S}/daemon/src/ctrl_gfx/mod.rs || die "Can't add nvidia device section to the gfx switcher."

    # adding vendor package config
    mkdir -p ${S}/.cargo && cp ${FILESDIR}/vendor_config ${S}/.cargo/config
    default
}

src_compile() {
    cargo_gen_config
    default
}

src_install() {
    insinto /etc/${_PN}
    doins data/${_PN}-ledmodes.toml

    # searching fo ra better solution (svg?)
    insinto /usr/share/icons/hicolor/512x512/apps/
    doins data/icons/*.png

    insinto /lib/udev/rules.d/
    doins data/${_PN}.rules

    if [ -f data/_asusctl ] && [ -d /usr/share/zsh/site-functions ]; then
        insinto /usr/share/zsh/site-functions
        doins data/_asusctl
    fi
    
    ## GFX
    if use gfx; then
        ## mod blacklisting
        insinto /etc/modprobe.d
        doins ${FILESDIR}/3.x/90-nvidia-blacklist.conf

        # xrandr settings for nvidia-primary (gnome only, will autofail on non-nvidia as primary)
        if use gnome; then
            insinto /etc/xdg/autostart
            doins "${FILESDIR}"/3.x/xrandr-nvidia.desktop

            insinto /usr/share/gdm/greeter/autostart
            doins "${FILESDIR}"/3.x/xrandr-nvidia.desktop
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

    if use acpi; then
        insinto /etc/modules-load.d
        doins ${FILESDIR}/90-acpi_call.conf
    fi

    use notify && cargo_src_install --path "asus-notify"
    cargo_src_install --path "asusctl"
    cargo_src_install --path "daemon"
    cargo_src_install --path "daemon-user"
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
