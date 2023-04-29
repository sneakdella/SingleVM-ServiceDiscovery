# SingleVM-ServiceDiscovery

# What does this do?

Only applicable for vRealize Operations 8.10 On-Premise at the moment

This script will (in it's current state) look up a single WindowsOS object in vROps 8.10 and read it's properties for Tags:services. It will then extract those service display names and service names.

Once it has the service display names and associated service name(s) it will then commit against the parent Virtual Machine object to command a service activation for the Windows Services.