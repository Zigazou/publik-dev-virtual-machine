Publik developer virtual machine creator
========================================

These scripts help you to create and run a Publik developer virtual machine.

IT IS NOT MEANT FOR PRODUCTION SITE!

because:

- passwords are too simple (publik/publik, admin/admin…),
- when used proxy authentication info is written in the ISO image,
- nothing has been done to enhance security compared to a stock Debian install.

You’ve been warned!

Publik is a web application from Entr’Ouvert targeted at authorities.

[More about Publik](https://publik.entrouvert.com/)

How to use it
-------------

You need a Debian or Ubuntu machine that will generate an ISO image and host the
VirtualBox virtual machine.

This means you need to have the VirtualBox application installed and running.

You need to download an AMD64 netinst ISO image from the Debian site, preferably
the 9.6.0 (stretch) version.

The scripts support installation from behind a Proxy.

Once everything is in the same directory, run the following in this order:

    ./gen-publik-iso.bash
    ./create-publik-vm.bash

Answers questions adequately

Once the installation is launched, all you need is wait approximately 30
minutes. If everything went well, you will see the following message:

    Publik developer instance has been installed.

    It runs on 192.168.0.16.
      
    You should access it using *.dev.publik.love domains.

    Connect using user=admin@localhost, password=admin

**Note**:

- IP address may vary as it is assigned by any available DHCP server on
  the network.
- The keyboard is set for french people.

On your computer, you need to have the following hosts names to be inserted in
your /etc/hosts file:

    192.168.0.16 agent-combo.dev.publik.love authentic.dev.publik.love
                 bijoe.dev.publik.love chrono.dev.publik.love 
                 combo.dev.publik.love fargo.dev.publik.love
                 hobo.dev.publik.love passerelle.dev.publik.love
                 wcs.dev.publik.love

**Note**: everything must be on the same line!

Once everything is set up, just visit https://authentic.dev.publik.love

