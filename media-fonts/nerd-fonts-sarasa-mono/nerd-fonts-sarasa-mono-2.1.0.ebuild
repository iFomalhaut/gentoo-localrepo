# Copyright 2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit font

DESCRIPTION="Sarasa Mono SC font patched with Nerd fonts"
HOMEPAGE="https://github.com/laishulu/Sarasa-Mono-SC-Nerd"
SRC_URI="https://github.com/laishulu/Sarasa-Mono-SC-Nerd/archive/refs/tags/v${PV}.zip -> ${P}.zip"

LICENSE="OFL-1.1"
SLOT="0"
KEYWORDS="amd64 ~riscv x86"

BDEPEND="app-arch/unzip"

S="${WORKDIR}/fonts/ttf"
FONT_SUFFIX="ttf
