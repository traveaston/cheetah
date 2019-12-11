# cheetah

CLI FLAC music transcoding tool with a focus on standardising tags

I like to keep a perfect digital replica of my CDs, and transcode them to MP3 V0 for listening on my iPhone.

The bash version of this simply requires copying/linking `cheetah.sh` into your `path`. It checks for missing dependencies when run and outputs an install string tailored to the local package manager.

bash was originally chosen as I was basically just looping a shell command  
`flac 'Song.flac' | lame - 'Song.mp3'`

I expanded the functionality quite a bit, and `bash` started to get in the way when I added features such as case manipulation and artist feature parsing.

**Case manipulation** was introduced in bash 4.0 and macOS ships with 3.2.  
This might not have been an issue eventually since Catalina brings zsh by default(?) which probably supports case manipulation(?) but it still sent me down the path of writing an Ansible script to install bash from homebrew and set my default shell to it.  
`Name Of Song.mp3` -> `Name of Song.mp3`

**Parsing / splitting features**: iTunes doesn't support multiple artists so I've decided to have a "main artist" (usually the artist I started listening to first or have the most music from) and move the collaborating artist into the features list in the song title.  
`Artist 1 & Artist 2 - Song Title (feat. Artist 3)` ->  
`Artist 1 - Song Title (feat. Artist 2, Artist 3)`

This got fairly complex in bash and I wrote some code that just didn't sit right with me regarding array helper methods and basically trying to return a python tuple from a bash function using a delimiter.

I wanted to write tests for cheetah (bats does do a decent job if the program is set up for it) and adding string reformatting for `feat.` was getting fairly complex and dealing with `sed/ssed`'s backwards bracket-handling regex implementation was also a source of frustration.

___

## Getting started

Required: Python 3, pip, virtualenv

Clone the repo  
`git clone https://github.com/traveaston/cheetah.git`

Enter the directory  
`cd cheetah`

Set up a virtual python environment (in a dir called `venv`) to avoid polluting your pip packages  
`virtualenv venv`

Activate the virtual environment by sourcing the shell script it creates  
`. venv/bin/activate`

Install the dependencies  
`pip install -r requirements.txt`

Run cheetah  
`./cheetah.py "~/rips/Artist - Album (2020) [XXX-ABC FLAC]"/`

Once I figure out packaging and distribution, there might be a helper script to activate venv and run cheetah from the correct place, otherwise it probably needs to be provided a full path, or enter the repo directory, source the activation script, and run from there every time.
