# gentoo-localrepo
My Gentoo local repository

Using repository with newer portage
-----------------------------------

Create a /etc/portage/repos.conf/iFomalhaut.conf file containing:

    [iFomalhaut]
    location  = /usr/local/portage/iFomalhaut
    sync-type = git
    sync-uri  = https://github.com/iFomalhaut/gentoo-localrepo.git
    priority  = 9999

Then run emerge --sync
