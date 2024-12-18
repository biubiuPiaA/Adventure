# Refer with https://sechurity.com/this-custom-script-literally-saved-me-from-failing-oscp/
# Helper script by @sechurity
# Create a log directory, a log file and start logging

#!/bin/bash 
if [ -z "${UNDER_SCRIPT}" ]; then
    logdir=${HOME}/logs
    logfile=${logdir}/$(date +%F.%H-%M-%S).$$.log

    # Create log directory if it doesn't exist
    mkdir -p ${logdir}

    # Remove log files older than 3 days
    find ${logdir} -type f -name "*.log" -mtime +3 -delete

    export UNDER_SCRIPT=${logfile}
    echo "The terminal output is saving to $logfile"
    script -f -q ${logfile}

    exit
fi
