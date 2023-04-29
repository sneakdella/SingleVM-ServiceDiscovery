# SingleVM-ServiceDiscovery
THIS SCRIPT IS STILL UNDER DEVELOPMENT AND INCOMPLETE
### Tl;dr
- This script will auto-create VMware Application Management Pack Services Objects for Windows OS Virtual Machines that have the VMware vRealize Operations Integrated Telegraf Agent Installed (Managed Agent). 
- There is a slight modification to the telegraf.emqtt.windows.conf file that is required first on the cloud proxy in which the managed telegraf agents are deployed from.
- The intent is to not have to touch the core infrastructure itself to gain the information needed (I.E. Running a Get-Service command on all of your servers). The idea is to use the vROps API only to accomplish this simple task.
- Please read below for more information.

### Why did I write this?
In vRealize Operations 6, the End Point Operations Manager agent was the main agent used to monitor the core Windows OS. This included an automatic discovery functionality to where you could configure the End Point Operations Manager Agent to automatically create Service objects in vROps 6 with a one liner command in the configuration file. 

When VMware made the move to vROps 8/VMware Aria Cloud SaaS, the End Point Operations Agent was replaced by the Telegraf Agent. While SDMP and Telegraf automatic discoveries work, they do not work in the previous way intended and is extremely limited to the known "built-in" services it can discover. 

There is no functionality that exists today in vROps 8/VMware Aria Cloud SaaS with the "managed" Telegraf Agent that replicates the automatic Windows Services object creation like End Point Operations Manager Agent did in the past. (Confirmed via an email between myself and VMware Success360 Support)
### Requirements

- vRealize Operations 8.10 (On-Premise)

- You will need to add **[[inputs.win_services]]** plugin to your telegraf.emqtt.windows.conf file on your vRealize Operations Cloud Proxy. This is located in /ucp/downloads/salt on each cloud proxy where you have the VMware Application Management Pack deployed to.

- If you already have telegraf deployed, you will need to re-install telegraf to have the **[[inputs.win_services]]** to apply to the Windows Server's specific Telegraf agent config.

### Display Name vs Service Name
A note before reading the script steps. Windows Services have two "names." One is their Display Name and the other is their Service Name.

I.E. 
- Display Name: **Windows Event Log**
- Service Name: **EventLog**

Unfortunately, it is not a simple pull from the vROps 8.10 API to get the Display Name, Service Name and Start-up mode all in one place. The Display Name and Start-up mode are under Metrics > Services for each service. While the actual Service Name is under Properties > Tags > Services for each service.

### A Note On "Services" Objects
There are two types of Services objects in vROps 8/VMware Aria Operations SaaS. They both use different adapters.

- VMWare vRealize Application Management Pack (Telegraf) ---- This is the Service object(s) the script is creating
- Service Discovery via VMware Tools (Native SDMP Discovery)

### Steps This Script Performs
/////// WORKING NOW ///////

- Look up a single WindowsOS object in vROps 8.10
- Pull it's Windows Services via the Windows OS object's Metrics > Services (To get the service's startup mode by display name) and return only the Windows Services set to automatic (value is 2) in the form of an ArrayList
- Pull it's Windows Services via the Windows OS object's Properties > Tags > Services (this is to get the Service Name), and remove the BlackListed services. It will return this as a Hastable
- The script will then take the ArrayList of Automatic Windows Services to match the Display Name with the Service Name and return a final hashtable of all automatic services with the correct information needed. "Display Name" and "Service Name"

/////// BELOW IS STILL IN DEVELOPMENT ///////

- Once it has the service display names and associated service name(s), the Parent Virtual Machine object is then queried for.
- The script will check the Parent Virtual Machine object if any of the services are already existing/collecting on the Virtual Machine. If they exist on the Virtual Machine object already, they will be removed from the hashtable. If they don't exist, they will stay in the hashtable. The hashtable is only intended to have objects that are not currently monitored.
- Once the final list of Windows Automatic Services are confirmed. It will then commit against the parent Virtual Machine object to command a service activation for the Windows Services listed in the hashtable.
