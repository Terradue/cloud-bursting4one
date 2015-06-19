#!/bin/sh

prefix="/var/lib/one/remotes"

# Creating the soft links
for driver in jclouds cloudstack
do
    # vmm
    src="${prefix}/vmm/bursting"
    dest="${prefix}/vmm/${driver}"
    ln -s ${src} ${dest}
    
    # im
    src="${prefix}/im/bursting.d"
    dest="${prefix}/im/${driver}.d"
    ln -s ${src} ${dest}
done

exit 0
