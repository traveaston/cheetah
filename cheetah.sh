#!/bin/bash
# cheetah
# transcoding tool

# Dependencies:
#   flac
#   id3v2
#   lame
#   metaflac
#   ssed
#   mktorrent
#   mediainfo

getInfo() {
  xml=$(mediainfo "$1" --Output=XML)
  echo $xml > /tmp/cheetah.xml

  while read_dom; do
    case $ENTITY in
      "Bit_rate_mode")
        brmode="$CONTENT"
        ;;
      "Encoding_settings")
        encoding="$CONTENT"
        ;;
      "Format")
        fileformat="$CONTENT"
        ;;
      "Overall_bit_rate")
        bitrate=$(regexNumOnly "$CONTENT")
        ;;
    esac
  done < /tmp/cheetah.xml
}

detectBitrate() {
  # reset all detected fields
  bitrate=""
  brtype="" # bit rate type: CBR/VBR
  encoding=""

  getInfo "$1"

  [[ $encoding == "" ]] && encoding="_blank_"

  echo "\"$1\""
  echo "Bitrate: ${GREEN}$bitrate kbps${D}"
  echo "Mode: ${GREEN}$brmode${D}"
  echo "Encoding: ${GREEN}$encoding${D}"
  echo
  echo "$1 is a $fileformat file"
}

buildFileName() {
  echo "test"
}

# music transcoding
# transcode V0 input.flac
transcode() {
  settings=""
  file=$(basename "$2")
  name="${file%.*}"

  case $1 in
    320)
      settings="--cbr -b 320"
      ;;
    V0)
      settings="-V 0"
      ;;
    *)
      echo "${RED}Must specify bitrate [320 / V0]${D}"
      return 0
      ;;
  esac

  title="$(metaflac --show-tag=title "$file" | sed 's/[^=]*=//')"
  artist="$(metaflac --show-tag=artist "$file" | sed 's/[^=]*=//')"
  album="$(metaflac --show-tag=album "$file" | sed 's/[^=]*=//')"
  year="$(metaflac --show-tag=date "$file" | sed 's/[^=]*=//')"
  tracknumber="$(metaflac --show-tag=tracknumber "$file" | sed 's/[^=]*=//')"
  genre="$(metaflac --show-tag=genre "$file" | sed 's/[^=]*=//')"

  # pad track number if not 2 digits
  [[ ${#tracknumber} == 1 ]] && tracknumber="0$tracknumber"

  # check if file exists then transcode
  # todo probably should ask to overwrite with a y/n/all
  [[ -f "$name.mp3" ]] && echo "File already exists: ${RED} $name.mp3 ${D}" ||
  flac -cds "$file" | lame -hS $settings --add-id3v2 --tt "$title" --ta "$artist" --tl "$album" --ty "$year" --tn "$tracknumber" --tg "$genre" - "$name.mp3"

  # TODO copy artwork from flac to mp3
  # TODO auto search google if art doesnt exist or is bigger than 512kb or smaller than 500x500
}

# transcodefolder V0
transcodefolder() {

  [[ -z "$1" ]] && echo "${RED}Must specify bitrate [320 / V0]${D}" || {
    bitrate="$1"
    echo "${GREEN}Transcoding all FLACs in this folder to MP3 $bitrate${D}"
    for i in *.flac; do
      transcode $bitrate "$i";
    done

    album=${PWD##*/}
    flacfolder=$(pwd)
    newfolder=$(echo $flacfolder | ssed "s/FLAC/$bitrate/i")

    if [[ "$flacfolder" == "$newfolder" ]]; then
      # Original folder name didn't include "FLAC", add bitrate to new folder name
      newfolder="$newfolder [$bitrate]"
    fi

    echo "${GREEN}Copying artwork and MP3s to $newfolder${D}"
    # Copy files and suppress errors
    rsync -a cover.* folder.* *.mp3 "$newfolder" 2>/dev/null

    echo "${GREEN}Removing all MP3s from current folder${D}"
    rm -rf *.mp3

    # notify "Finished transcoding $album to MP3 $bitrate"
    echo
    echo "${GREEN}Finished transcoding $album to MP3 $bitrate${D}"
  }
}

gentorrent() {
  [[ -z $1 ]] && echo "usage: gentorrent path/to/folder" ||
  {
    announce="https://_TRACKER_URL_/_ANNOUNCE_PASSKEY_/announce"
    folder="$1"
    torrent="$folder.torrent"

    mktorrent -p -a $announce -o "$torrent" "$folder"
  }
}

# Read xml files
read_dom () {
  local IFS=\>
  read -d \< ENTITY CONTENT
}

# Regex remove any char not numeric
regexNumOnly() {
  echo "$@" | sed 's/[^0-9]*//g'
}

# Colours
D=$'\e[37;49m'
BLUE=$'\e[34;49m'
CYAN=$'\e[36;49m'
GREEN=$'\e[32;49m'
ORANGE=$'\e[33;49m'
PINK=$'\e[35;49m'
RED=$'\e[31;49m'

# Execute main
# cheetah

# Exit if no file specified
[[ -z "$1" ]] &&
{
  # They want to do the current folder
  current_folder=${PWD##*/}
  echo "Assuming current folder - ${RED}$current_folder${D}?"
  # echo "(this will fuck your shit up if you run it in the wrong place)"
  intent="dir"
  # read -rsp $'Press any key to continue...\n' -n1 key
  # echo "${RED}Look mate, you gotta specify a file to detect${D}"
  # echo "cheetah file.mp3" # TODO naming
  # exit 1
}

if [[ "$1" == "info" ]]; then
  # Show tag info on the specified file
  file="$2"
  getInfo "$file"

  if [[ "$fileformat" == "FLAC" ]]; then
    metaflac --list --block-number=2 "$file"
  elif [[ "$fileformat" == "MPEG Audio" ]]; then
    id3v2 -l "$file"
  else
    echo $fileformat
  fi
fi
# exit 1

# Exit if file doesn't exist
[[ -f "$1" ]] && intent="file"
[[ -d "$1" ]] && intent="dir"

[[ "$intent" == "" ]] &&
{
  echo "\"$1\" doesn't exist in this dir, pay more attention to history before running it"
  exit 1
}

# TODO REMOVE BELOW
# echo "Intent is for ${BLUE}$intent${D}"

if [[ "$intent" == "file" ]]; then
  detectBitrate "$1"
elif [[ "$intent" == "dir" ]]; then
  read -p "Bitrate to transcode folder? " bitrate

  transcodefolder "$bitrate"
fi
