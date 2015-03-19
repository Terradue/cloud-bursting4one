Cloud Bursting Driver for Opennebula
====================================

Installation
-------------

* To install type:

```bash
sudo yum install -y cloud-bursting4one
```

The generic bursting driver includes the following child drivers:

* jclouds
* cloudstack (upcoming!)

Configuration
-------------

General
^^^^^^^

* To configure general settings for a child driver, just edit the file /etc/one/<driver_name>_driver.conf*. For example for *jclouds*:

```bash
jclouds_cmd: /usr/bin/jclouds-cli
context_path: /data/cloud/remote_context/jclouds/iso
```

Accounts
^^^^^^^^

* To configure the accounts for a child driver, just edit the file /etc/one/<driver_name>_driver.conf. For example for *jclouds*:

```bash
hosts:
    ec2-eceo:
        provider: aws-ec2
        identity: <identity>
        credential: <credential>
        capacity:
            m1.small: 5
            m1.large: 0
            m1.xlarge: 0
    ec2-ows10-sbas:
        provider: aws-ec2
        identity: <identity>
        credential: <credential>
        capacity:
            m1.small: 5
            m1.large: 0
            m1.xlarge: 0
```

Opennebula
^^^^^^^^^^

* Edit the file */etc/one/oned.conf*, adding the following lines for each child driver you want to configure:

```bash
#-------------------------------------------------------------------------------
#  jclouds Virtualization Driver Manager Configuration
#    -r number of retries when monitoring a host
#    -t number of threads, i.e. number of actions performed at the same time
#-------------------------------------------------------------------------------
VM_MAD = [
    name       = "jclouds",
    executable = "one_vmm_sh",
    arguments  = "-t 15 -r 0 jclouds",
    default    = "vmm_exec/vmm_exec_jclouds.conf",
    type       = "xml" ]
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#  jclouds Information Driver Manager Configuration
#    -r number of retries when monitoring a host
#    -t number of threads, i.e. number of hosts monitored at the same time
#-------------------------------------------------------------------------------
IM_MAD = [
      name       = "jclouds",
      executable = "one_im_sh",
      arguments  = "-c -t 1 -r 0 jclouds" ]
#-------------------------------------------------------------------------------
```

* Restart the core service:

```bash
su - oneadmin one stop
su - oneadmin one start
```