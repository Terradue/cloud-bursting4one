# cloud-bursting4one

The cloud-bursting4one driver is an OpenNebula add-on that implements hybrid Cloud computing, with the ability to support Cloud bursting on a variety of public Cloud providers. It's modular design eases the integration of new Cloud provider APIs. Currently it supports the [Apache Jclouds library](<https://jclouds.apache.org/>) and the [CloudStack API](<https://cloudstack.apache.org/>). Future developments will support the [OCCI API](http://occi-wg.org/).
It is a generalization of the previous Opennebula add-on [jclouds4one](https://github.com/OpenNebula/addon-jclouds4one).
This work has been co-funded by the European Commission (EC) in the context of the FP7 [SenSyF](<http://www.sensyf.eu>) project.


## Authors

* Cesare Rossi (cesare.rossi[at]terradue.com)

## Compatibility

This add-on is compatible with OpenNebula 4.10.

## Features

Implements hybrid Cloud computing, to support Cloud bursting, with the ability to work with a variety of Cloud provider, such as:

* Amazon AWS
* Azure Management
* Cloud Stack
* ElasticHosts
* GleSYS
* Go2Cloud
* GoGrid
* HP Cloud Services
* Ninefold
* OpenStack

## Limitations

It is not tested with all the listed providers, so contributions in this matter are appreciated.

## Installation by RPM

This project is developed with Maven and the RPM provided with the rpm-maven-plugin (read `pom.xml`). Once you have built the project, install the package by:

```bash
rpm -Uvh cloud-bursting4one.rpm
```

## Manual Installation

To manually install the driver, you have to download the repository as a ZIP:

```bash
unzip cloud-bursting4one-master.zip
cd cloud-bursting4one
```

Copy the main driver files in the Opennebula installation directory:

```bash
ONE_DIR=<your Opennebula installation dir>
cp src/main/resources/remotes/vmm/bursting ${ONE_DIR}/remotes/vmm/bursting
cp src/main/resources/remotes/im/bursting.d ${ONE_DIR}/remotes/im/bursting.d
```

Create the soft links needed for each API driver:

```bash
cd ${ONE_DIR}/remotes
for api in jclouds cloudstack; do ln -s vmm/bursting vmm/${api}; done 
for api in jclouds cloudstack; do ln -s im/bursting.d im/${api}.d; done
```

Copy the configuration driver files in the Opennebula configuration directory:

```bash
ONE_CONF=<your Opennebula configuration dir>
cp src/main/resources/etc/ ${ONE_CONF}
```

# Configuration

The cloud-bursting4one driver includes the following interfaces:

* jclouds
* cloudstack

## API driver configuration

* To configure the *general settings* for an API driver, just edit the file /etc/one/*api*_driver.conf. For example for *jclouds*:

```bash
jclouds_cmd: /usr/bin/jclouds-cli
context_path: /cloud/remote_context/jclouds/iso
```

* To configure the *accounts* for an API driver, just edit the file /etc/one/*api*_driver.conf. For example for *jclouds*:

```bash
hosts:
    ec2-accountA:
        provider: aws-ec2
        identity: <identity>
        credential: <credential>
        capacity:
            m1.small: 5
            m1.large: 0
            m1.xlarge: 0
    ec2-accountB:
        provider: aws-ec2
        identity: <identity>
        credential: <credential>
        capacity:
            m1.small: 5
            m1.large: 0
            m1.xlarge: 0
```

*NOTE*

Depending on the API driver, the content of the configuration file could be different. Examples of configurations are provided in the code.

## Opennebula core configuration

* Edit the file */etc/one/oned.conf*, adding the following lines for each child driver you want to configure:

```bash
VM_MAD = [
    name       = "jclouds",
    executable = "one_vmm_sh",
    arguments  = "-t 15 -r 0 jclouds",
    default    = "vmm_exec/vmm_exec_jclouds.conf",
    type       = "xml" ]

IM_MAD = [
      name       = "jclouds",
      executable = "one_im_sh",
      arguments  = "-c -t 1 -r 0 jclouds" ]
```

* Restart the core service:

```bash
su - oneadmin 'one stop; one start'
```

# Usage

## Setup the cluster

* Create the cluster:

```bash
su - oneadmin onecluster create bursting
```

## Setup the host

* Create the host: (TODO: Check how to specify the cluster)

```bash
su - oneadmin
onehost create ec-accountA --im jclouds --vm jclouds --net dummy
```

## Prepare the virtual template

* Prepare a template suitable for the cloud-bursting4one driver, using either the Sunstone GUI or the following commands:

```bash
cat ec2_template.txt

NAME="EC2 VM"
CONTEXT=[
    FILES=""
  ]
PUBLIC=[
    GROUP="default",
    HARDWAREID="t1.micro",
    LOCATIONID="us-east-1d"
  ]
```
```bash
onetemplate create jclouds.txt
```

## Start the virtual machine

Finally start the VM, using the template just created.

## Development

To contribute bug patches or new features for cloud-bursting4one, you can use the github Pull Request model. It is assumed that code and documentation are contributed under the Apache License 2.0.

To extend the driver with an additional API, it is enough:

* Add a wrapper Ruby class under *src/main/resources/remotes/vmm/bursting/drivers/* which extends the *BurstingDriver* class and implements the bursting actions.

* Add a type for the new API driver in *src/main/resources/remotes/vmm/bursting/drivers/bursting_driver.rb*, see for example this code snippet: 

```ruby
DRIVERS = {
    :jclouds    => 'jclouds',
    :cloudstack => 'cloudstack'
  }

  def self.create(type,host)

    case type
    when DRIVERS[:jclouds]
      JcloudsDriver.new(host)
    when DRIVERS[:cloudstack]
      CloudStackDriver.new(host)
    else
      raise "Bad bursting driver type: #{type}"
    end
  end
```

* Add the configuration files under *src/main/resources/etc/*

That's all :-)

## References

* OpenNebula: http://opennebula.org/ 
* jclouds: http://jclouds.apache.org/
* CloudStack: https://cloudstack.apache.org/