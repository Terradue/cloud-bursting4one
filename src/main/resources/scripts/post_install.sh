#!/bin/sh

_INSTALL=1
_UPGRADE=2

# Checks if it's a first installation or an upgrade
# Ref. https://fedoraproject.org/wiki/Packaging:ScriptletSnippets#Syntax
if [ $1 == $_INSTALL ]
then
    # General
    # requirements
    /usr/bin/gem install jsonpath --version '0.5.6'

    # log folder
    mkdir -p /var/log/one/bursting

    # Cloudstack driver
    # requirements
    /usr/bin/easy_install cloudmonkey==5.3.1

    # OCCI driver
    # requirements
    /usr/bin/gem install occi-api

    # destination folder for the generated user proxies
    mkdir -p /var/lib/occi/proxies/

    # libcloudcli
    /opt/miniconda2/bin/conda install libcloudcli -y
fi

exit 0
