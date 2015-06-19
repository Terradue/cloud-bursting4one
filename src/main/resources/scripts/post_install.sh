#!/bin/sh

prefix="/var/lib/one/remotes"

# Creating the soft links
for driver in jclouds cloudstack
do
    # vmm
    src="${prefix}/vmm/bursting"
    dest="${prefix}/vmm/${driver}"
    
    if [[ ! -h "${dest}" ]]
    then
      ln -s ${src} ${dest}
    fi
    
    # im
    src="${prefix}/im/bursting.d"
    dest="${prefix}/im/${driver}.d"
    
    if [[ ! -h "${dest}" ]]
    then
      ln -s ${src} ${dest}
    fi
done

echo "Post-install done."

exit 0
