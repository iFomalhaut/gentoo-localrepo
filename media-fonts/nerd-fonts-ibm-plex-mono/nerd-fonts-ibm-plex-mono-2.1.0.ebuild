# Copyright 2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit font

DESCRIPTION="A Nerd Font patched version of IBM Plex™ Mono"
HOMEPAGE="https://www.nerdfonts.com"
SRC_URI="https://github.com/ryanoasis/nerd-fonts/releases/download/v${PV}/IBMPlexMono.zip -> ${P}.zip"

LICENSE="MIT"
SLOT="0"
KEYWORDS="amd64 ~riscv x86"

BDEPEND="app-arch/unzip"

S="${WORKDIR}/fonts/ttf"
FONT_SUFFIX="ttf
