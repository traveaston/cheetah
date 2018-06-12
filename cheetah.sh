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
  mediainfo
  # metaflac is part of flac
  mktorrent
  rsync
  ssed
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
  printf "\rProgress: [${_done// /#}${_left// /-}] ${_progress}%%  "
}

# transcode V0 /path/input.flac ~/outputfolder/
transcode() {
  settings=""
  bitrate="$1"
  file="$2"
  folder="${3%/}" # remove trailing slash

  [[ -z "$folder" ]] && folder="."

  [[ ! -w "$folder" ]] && echo "directory ${RED}$folder${D} is not writable, exiting" && exit 1

  case $bitrate in
    320)
      settings="--cbr -b 320"
      ;;
    v*|V*)
      settings="-V ${bitrate:1:2}"
      ;;
    *)
      echo "${RED}Must specify bitrate [320/V0/etc]${D}"
      exit 1
      ;;
  esac

  title="$(metaflac --show-tag=title "$file" | sed 's/[^=]*=//')"
  artist="$(metaflac --show-tag=artist "$file" | sed 's/[^=]*=//')"
  album="$(metaflac --show-tag=album "$file" | sed 's/[^=]*=//')"
  year="$(metaflac --show-tag=date "$file" | sed 's/[^=]*=//' | sed -E 's/^([0-9]{4}).*$/\1/')" # ensure year is 4 digits
  tracknumber="$(metaflac --show-tag=tracknumber "$file" | sed 's/[^=]*=//')"
  genre="$(metaflac --show-tag=genre "$file" | sed 's/[^=]*=//')"

  # change tracknumber '2/11' to '2'
  tracknumber=$(echo $tracknumber | cut -f1 -d"/")

  # pad track number if not 2 digits
  [[ ${#tracknumber} == 1 ]] && tracknumber="0$tracknumber"

  # strip anything after second character
  [[ ${#tracknumber} != 2 ]] && tracknumber="${tracknumber:0:2}"

  # Replace illegal characters with dash
  sanitisedtitle="$(echo $title | sed 's/[?:;*\/]/-/g')"

  # Replace original filename with custom name
  output_file="$folder/$tracknumber $sanitisedtitle.mp3"

  # ensure file doesn't already exist
  [[ -f "$output_file" ]] && echo "File already exists: ${RED}$output_file${D}" && exit 1 ||
  flac -cds "$file" | lame -h --silent $settings --add-id3v2 --tt "$title" --ta "$artist" --tl "$album" --tv TPE2="$artist" --ty "$year" --tn "$tracknumber/$totaltracks" --tg "$genre" - "$output_file"
}

# transcodefolder V0 source
transcodefolder() {
  bitrate="$1"
  [[ -z "$bitrate" ]] && echo "${RED}Must specify bitrate [320/V0/etc]${D}" && exit 1

  cd "$2"

  album=${PWD##*/}
  in_path=$(pwd)
  out_path=$(echo $in_path | ssed "s/FLAC/$bitrate/i")

  # append bitrate to folder if original folder omitted "FLAC", failing substitution
  [[ "$in_path" == "$out_path" ]] && out_path="$out_path [$bitrate]"

  totaltracks=$(ls -1qU *.flac | wc -l | awk '{print $1}')

  # if directory already exists, ensure it's empty
  [[ -d "$out_path" ]] && [[ "$(ls -A "$out_path")" ]] && echo "${RED}$out_path${D} already exists, exiting" && exit 1
  mkdir -p "$out_path"

  [[ ! -w "$out_path" ]] && echo "directory ${RED}$out_path${D} is not writable, exiting" && exit 1

  echo "Transcoding ${RED}$totaltracks${D} FLACs in ${RED}$album${D} to MP3 $bitrate"
  counter=0
  for i in *.flac; do
    progressbar $counter $totaltracks
    transcode $bitrate "$i" "$out_path"
    counter=$((counter+1))
  done
  progressbar $counter $totaltracks && echo

  rsync -a cover.* folder.* *.jpg "$out_path" 2>/dev/null

  # notify "Finished transcoding $album to MP3 $bitrate"
  echo "$bitrate transcode output to ${BLUE}$out_path${D}"
}

function searchAlbumArt() {
  # Remove illegal characters, encode spaces
  search="$(echo "$album $artist $year" | sed 's/ /+/g' | sed 's/[?:;*&\/\\]//g')"

  echo "Search google for cover art:"
  echo "https://google.com/search?safe=off&tbs=imgo:1,isz:lt,islt:qsvga&tbm=isch&q=$search"
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

target=${1%/} # strip trailing slash

# Assume current folder if no target specified
[[ -z "$target" ]] && target="."

if [[ "$target" == "info" ]]; then
  # cheetah info "01 Song.flac"
  # Show tag info on the specified file
  target="$2"
  getInfo "$target"

  if [[ "$fileformat" == "FLAC" ]]; then
    metaflac --list --block-number=2 "$target"
  elif [[ "$fileformat" == "MPEG Audio" ]]; then
    id3v2 -l "$target"
  else
    echo $fileformat
  fi

  echo
  detectBitrate "$target"
  exit 1
elif [[ -f "$target" ]]; then
  # file
  read -p "Bitrate to transcode file [V0]: " bitrate
  [[ "$bitrate" == "" ]] && bitrate="V0"

  transcode "$bitrate" "$target" "$2"
  echo "$bitrate transcode output to ${BLUE}$output_file${D}"
elif [[ -d "$target" ]]; then
  # folder
  read -p "Bitrate to transcode folder [V0]: " bitrate
  [[ "$bitrate" == "" ]] && bitrate="V0"

  transcodefolder "$bitrate" "$target"
  searchAlbumArt
else
  # Exit if file doesn't exist
  echo "Cannot find file or folder \"$target\""
  exit 1
fi
