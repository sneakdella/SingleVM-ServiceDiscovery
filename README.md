# SingleVM-ServiceDiscovery
THIS SCRIPT IS STILL UNDER DEVELOPMENT AND INCOMPLETE: Add-WindowsOSServices.psm1

THIS OTHER SCRIPT IS TO GRAB ALL WINOS OBJECTS, IT IS ALSO INCOMPLETE: Get-VMsWithTelegrafInstalled.psm1
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
- The script will then take the ArrayList of Automatic Windows Services to match the Display Name with the Service Name and return a hashtable of all automatic services with the correct information needed ("Display Name" and "Service Name"). This is all then stored in the variable **$FinalFromWinOSObj**
- Once it has the service display names and associated service name(s), the Parent Virtual Machine object is then queried for. The UID is needed to commit the new Windows Services to be monitored if any are found.
- The script will then obtain a list of all the CHILD objects of the Windows OS object that are of the serviceavailability custom monitoring type. Here it will retireve the name of the service ("Windows Event Log on SERVERA") plus the "FILTER_VALUE" which would be the service's name (continuing the example, "EventLog"). It will dump these two values per object into a hashtable, but trim off the "on SERVERA" for the display name. Service Display Name is the key, Service Name "EventLog" would again be the value. This hashtable is stored in the variable named **$ServicesMonitored**
- The $FinalFromWinOSObj and $ServicesMonitored hashtables are then compared to ensure the script isn't trying to commit a Windows Service that is already monitored by VMware Aria Operations. This will return a hashtable stored in the variable **$ServicesToAdd**. (Gee, finally, that took long enough)
- Once the final list of Windows Automatic Services are confirmed. It will then commit against the parent Virtual Machine object to command a service activation for the Windows Services listed in the hashtable.
- Add global variable to have script accept a WindowsOS Object ID. Right now the script is on a singular UID from my dev environment.
- Turn entire script into Powershell Module (PSM1)
- Add a "What-If" option to show what services would be added without committing anything

/////// TO DO ///////
- Add functional debug parameters to each function (considering not doing this but whatever)

### Final Notes

- Missing a few commit history entries since I attempted to rebase my previous commits with the correct author name (me). I believe this is fixed now.
- Working on converting this to work with all Windows OS objects.... uhhhh not sure how to change the name of the repository yet. Ill figure it out.