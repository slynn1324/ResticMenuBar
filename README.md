#  ResticMenuBar

A simple SwiftUI MenuBarExtra application to periodically run a restic backup script and monitor the status.

Could be modified to run effectively any shell script.


## Why?

Apple macOS has really good application level sandboxing and file access permissions management, and it assigns that to the top level invoking application.  I didn't want to grant something as generic as SwiftBar all of the necessary access to backup my full home directory, as that access would be inherited by _any_ swiftbar script.  By building a custom app, the permission assignment is granted only to this application.  

Also, I wanted to be able to have some indication that my backups have been running and are healthy, and be able to quickly see that things are running as expected.

And I _sort of_ learned something by hacking my way through this.

Alternatively, I've just setup cron to run a backup script -- like I do on my Linux machines -- but it doesn't give good visualization without external monitoring, and requires you to grant permissions to `cron` which also feels weird. 

## Setup

On first launch, the application will create the folder ~/Library/Application Support/ResticMenuBar.  The folder can be opened via the menu item. 

Place a `run.sh` script in this folder that executes your restic backup job as desired (and/or really anything else you want to happen in relation to it).  Be sure that you mark it executable (chmod +x run.sh).  

Notes:

When `run.sh` is invoked, the current working directory is set to `~/Library/Application Support/ResticMenuBar`.

You will likely want to use absolute paths for binaries and resources, as the full path used in a terminal may not be present when the script is invoked.   


## Attribution

Icons from https://tabler.io/ (MIT Licensed)


