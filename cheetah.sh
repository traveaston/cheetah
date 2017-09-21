#!/bin/bash
# cheetah
# transcoding tool

# check dependencies are installed
dependenciesOkay=true
missingDependencies=()
dependencies=(
  flac
  id3v2
  lame
  # metaflac is part of flac
  ssed
  mktorrent
  mediainfo
)

for i in ${dependencies[@]}; do
  if ! command -v $i >/dev/null 2>&1 ; then
    dependenciesOkay=false
    missingDependencies+=($i)
  fi
done

[[ $dependenciesOkay == false ]] && {
  printf 'Missing dependencies: %s\n' "${missingDependencies[*]}"
  echo "Please install them before using cheetah"
  exit
}

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

# Author: Teddy Skarin
# progressbar currentState($1) and totalState($2)
# output: Progress: [########################################] 100%
function progressbar {
  # process data
  let _progress=(10#${1}*100/${2})
  let _done=(${_progress}*4)/10
  let _left=40-$_done

  # build progressbar string lengths
  _done=$(printf "%${_done}s")
  _left=$(printf "%${_left}s")

  # build progressbar strings and print the progressbar line
  printf "\rProgress: [${_done// /#}${_left// /-}] ${_progress}%%"
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
    V2)
      settings="-V 2"
      ;;
    *)
      echo "${RED}Must specify bitrate [320 / V0 / V2]${D}"
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

  # strip anything after second character
  [[ ${#tracknumber} != 2 ]] && tracknumber="${tracknumber:0:2}"

  # Replace asterisks and slashes with dashes
  sanitisedtitle="$(echo $title | sed 's/*/-/g' | sed 's/\//-/g')"

  # Replace original filename with custom name
  name="$tracknumber $sanitisedtitle"

  # check if file exists then transcode
  # todo probably should ask to overwrite with a y/n/all
  [[ -f "$name.mp3" ]] && echo "File already exists: ${RED} $name.mp3 ${D}" ||
  flac -cds "$file" | lame -h --silent $settings --add-id3v2 --tt "$title" --ta "$artist" --tl "$album" --tv TPE2="$artist" --ty "$year" --tn "$tracknumber/$totaltracks" --tg "$genre" - "$name.mp3"

  progressbar $tracknumber $totaltracks

  # TODO copy artwork from flac to mp3
  # TODO auto search google if art doesnt exist or is bigger than 512kb or smaller than 500x500
}

# transcodefolder V0
transcodefolder() {

  [[ -z "$1" ]] && echo "${RED}Must specify bitrate [320 / V0]${D}" || {
    bitrate="$1"

    totaltracks="$(ls -l *.flac | wc -l)"
    read -p "Assuming total track count is ${BLUE}$totaltracks${D}? [y]: " ttconfirm
    [[ "$ttconfirm" == "" ]] && ttconfirm="y"
    if ! [[ "$ttconfirm" == "y" ]]; then
      re='^[0-9]+$'
      if [[ $ttconfirm =~ $re ]]; then
        totaltracks=$ttconfirm
        echo "Total tracks: $totaltracks"
      else
        echo "Type number of tracks"
        exit 1
      fi
    fi

    echo "${GREEN}Transcoding all FLACs in this folder to MP3 $bitrate${D}"
    # start progress bar
    progressbar 0 $totaltracks
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

    # echo newline because progressbar ends without one
    echo
    echo "Moving files to $newfolder"
    mkdir -p "$newfolder"
    mv *.mp3 "$newfolder"/
    rsync -a cover.* folder.* *.jpg "$newfolder" 2>/dev/null

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

# Assume folder contents if no file specified
[[ -z "$1" ]] &&
{
  current_folder=${PWD##*/}
  echo "Assuming current folder - ${RED}$current_folder${D}?"
  intent="dir"
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

  echo
  detectBitrate "$file"
  exit 1
fi

# Exit if file doesn't exist
[[ -f "$1" ]] && intent="file"
[[ -d "$1" ]] && intent="dir"

[[ "$intent" == "" ]] &&
{
  echo "\"$1\" doesn't exist in this dir, pay more attention to history before running it"
  exit 1
}

if [[ "$intent" == "file" ]]; then
  read -p "Bitrate to transcode file [V0]: " bitrate
  [[ "$bitrate" == "" ]] && bitrate="V0"
  transcode "$bitrate" "$1"
elif [[ "$intent" == "dir" ]]; then
  read -p "Bitrate to transcode folder [V0]: " bitrate
  [[ "$bitrate" == "" ]] && bitrate="V0"

  transcodefolder "$bitrate"
fi
