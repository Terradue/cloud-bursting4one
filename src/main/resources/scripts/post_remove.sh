#!/bin/sh

prefix="/var/lib/one/remotes"

# Removing the soft links
for driver in jclouds cloudstack occi
do
    # vmm
    dest="${prefix}/vmm/${driver}"
    
    if [[ -h "${dest}" ]]
    then
      rm -f ${dest}
    fi
    
    # im
    dest="${prefix}/im/${driver}.d"
    
    if [[ -h "${dest}" ]]
    then
      rm -f ${dest}
    fi
done


    # libcloudcli
    /opt/anaconda/bin/conda remove libcloudcli -y


exit 0
