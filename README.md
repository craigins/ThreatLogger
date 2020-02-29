# ThreatLogger
Threat logger for World of Warcraft Classic

Usage:

/tlog start 
  enable threat logging
/tlog stop
  disable threat logging
/tlog status
  displays logging status (started/stopped) and number of targets logged
/tlog reset
  clears the logged information
  
  
File Location:

Logged threat is stored in an account wide SavedVariable.  Logs can be large so one log per character may be overkill.  The file can be found in your account SavedVariables directory:

World of Warcraft\_classic_\WTF\Account\<account>\SavedVariables



Viewing:

The server directory holds a simple nodejs application based off expressjs.

npm install
npm run main

Open Chrome and browse to http://localhost:3000/

Click the choose file button and locate the file from SavedVariables.  (note it might be a good idea to copy to a common directory to avoid overwriting the log with subsquent logins)

Select a fight from the list to view the threat graph