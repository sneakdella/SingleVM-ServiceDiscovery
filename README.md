# SingleVM-ServiceDiscovery

# What does this do?

Only applicable for vRealize Operations 8.10 On-Premise at the moment

This script will (in it's current state) look up a single WindowsOS object in vROps 8.10 and read it's properties for Tags:services. It will then extract those service display names and service names.

In the future:
It will only do automatic windows services (state 3)

Once it has the service display names and associated service name(s) it will then commit against the parent Virtual Machine object to command a service activation for the Windows Services.

# Hard requirements
vRealize Operations 8.10

You will need to add **[[inputs.win_services]]** plugin to your telegraf.emqtt.windows.conf file on your vRealize Operations Cloud Proxy. This is located in /ucp/downloads/salt on each cloud proxy where you have the VMware Application Management Pack deployed to.

If you already have telegraf deployed, you will need to re-install telegraf to have the **[[inputs.win_services]]** to apply to the Windows Server's specific Telegraf agent config.