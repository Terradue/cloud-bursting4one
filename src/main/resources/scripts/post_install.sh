#!/bin/sh

# General
# requirements
/usr/bin/gem install jsonpath --version '0.5.6'

# Cloudstack driver
# requirements
/usr/bin/easy_install cloudmonkey==5.3.1

# OCCI driver
# requirements
/usr/bin/gem install occi-api

# destination folder for the generated user proxies
mkdir -p /var/lib/occi/proxies/

exit 0
