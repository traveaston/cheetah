#!/usr/bin/env bash
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

for i in "${dependencies[@]}"; do
  if ! command -v "$i" >/dev/null 2>&1 ; then
    dependenciesOkay=false
    missingDependencies+=("$i")
  fi
done

[[ $dependenciesOkay == false ]] && {
  printf 'Missing dependencies: %s\n' "${missingDependencies[*]}"
  echo "Please install them before using cheetah"
  exit
}

getInfo() {
  xml=$(mediainfo "$1" --Output=XML)
  echo "$xml" > /tmp/cheetah.xml

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
progressbar() {
  # process data
  local _progress=$(( 10#${1}*100/${2} ))
  local _done=$(( (${_progress}*4)/10 ))
  local _left=$(( 40-$_done ))

  # build progressbar string lengths
  _done=$(printf "%${_done}s")
  _left=$(printf "%${_left}s")

  # build progressbar strings and print the progressbar line
  printf "\rProgress: [${_done// /#}${_left// /-}] ${_progress}%%  "
}

# transcode V0 /path/input.flac ~/outputfolder/
transcode() {
  local title artist album year tracknumber genre
  local main_artist feat_artist
  local output_file sanitisedtitle settings

  local bitrate="$1"
  local file="$2"
  local folder="${3%/}" # remove trailing slash

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
  tracknumber=$(echo "$tracknumber" | cut -f1 -d"/")

  # pad track number if not 2 digits
  [[ ${#tracknumber} == 1 ]] && tracknumber="0$tracknumber"

  # strip anything after second character
  [[ ${#tracknumber} != 2 ]] && tracknumber="${tracknumber:0:2}"

  # check bool, move featured artists into title (split by comma)
  [[ $split_featured && $artist == *','* ]] && {
    main_artist="${artist%%,*}"
    feat_artist="${artist#*,}"

    artist="$main_artist"

    # add features to title, and squash multiple spaces
    title="$(echo "$title (feat. $feat_artist)" | awk '{$1=$1;print}')"
  }

  # Replace illegal characters with dash
  sanitisedtitle="$(echo "$title" | sed 's/[?:;*\/]/-/g')"

  # Replace original filename with custom name
  output_file="$folder/$tracknumber $sanitisedtitle.mp3"

  if [[ -f "$output_file" ]]; then
    echo "File already exists: ${RED}$output_file${D}"
    exit 1
  else
    # shellcheck disable=SC2086 # $settings var is multiple flags, quotes are unfavorable
    flac -cds "$file" | lame -h --silent $settings --add-id3v2 --tt "$title" --ta "$artist" --tl "$album" --tv TPE2="$artist" --ty "$year" --tn "$tracknumber/$totaltracks" --tg "$genre" - "$output_file"
  fi
}

# transcodefolder V0 source
transcodefolder() {
  bitrate="$1"
  [[ -z "$bitrate" ]] && echo "${RED}Must specify bitrate [320/V0/etc]${D}" && exit 1

  cd "$2"

  album=${PWD##*/}
  in_path=$(pwd)
  out_path=$(echo "$in_path" | ssed "s/FLAC/$bitrate/i")

  # append bitrate to folder if original folder omitted "FLAC", failing substitution
  [[ "$in_path" == "$out_path" ]] && out_path="$out_path [$bitrate]"

  totaltracks=$(ls -1qU *.flac | wc -l | awk '{print $1}')

  # ensure there are files to transcode
  [[ $totaltracks == 0 ]] && {
    echo "${RED}No FLACs found. For multiple discs, run cheetah on each disc individually${D}"

    # echo sample commands for multiple discs
    find * -type d -print0 | while read -r -d $'\0' disc
    do
      echo "${BLUE}cheetah \"$album/$disc\"${D}"
    done

    exit
  }

  # if directory already exists, ensure it's empty
  [[ -d "$out_path" ]] && [[ "$(ls -A "$out_path")" ]] && echo "${RED}$out_path${D} already exists, exiting" && exit 1
  mkdir -p "$out_path"

  [[ ! -w "$out_path" ]] && echo "directory ${RED}$out_path${D} is not writable, exiting" && exit 1

  echo "Transcoding ${RED}$totaltracks${D} FLACs in ${RED}$album${D} to MP3 $bitrate"
  counter=0
  for i in *.flac; do
    progressbar $counter "$totaltracks"
    transcode "$bitrate" "$i" "$out_path"
    counter=$(( counter+1 ))
  done
  progressbar $counter "$totaltracks" && echo

  rsync -a cover.* folder.* *.jpg "$out_path" 2>/dev/null

  # notify "Finished transcoding $album to MP3 $bitrate"
  echo "$bitrate transcode output to ${BLUE}$out_path${D}"
}

searchAlbumArt() {
  # Remove illegal characters, encode spaces
  search="$(echo "$album $artist $year" | sed 's/ /+/g' | sed 's/[?:;*&\/\\]//g')"

  echo "Search google for cover art:"
  echo "https://google.com/search?safe=off&tbs=imgo:1,isz:lt,islt:qsvga&tbm=isch&q=$search"
}

# Read xml files
read_dom () {
  local IFS=\>
  read -r -d \< ENTITY CONTENT
}

# Regex remove any char not numeric
regexNumOnly() {
  echo "$@" | sed 's/[^0-9]*//g'
}

# Colours
D=$'\e[37;49m'
BLUE=$'\e[34;49m'
GREEN=$'\e[32;49m'
RED=$'\e[31;49m'

# Execute main
# cheetah

target=${1%/} # strip trailing slash
split_featured=true

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
    echo "$fileformat"
  fi

  echo
  detectBitrate "$target"
  exit 1
elif [[ -f "$target" ]]; then
  # file
  read -r -p "Bitrate to transcode file [V0]: " bitrate
  [[ "$bitrate" == "" ]] && bitrate="V0"

  transcode "$bitrate" "$target" "$2"
  echo "$bitrate transcode output to ${BLUE}$output_file${D}"
elif [[ -d "$target" ]]; then
  # folder
  read -r -p "Bitrate to transcode folder [V0]: " bitrate
  [[ "$bitrate" == "" ]] && bitrate="V0"

  # strip everything after " - " (leaving only the artist) and check for commas
  # ensures "I, Robot" isn't formatted as "I - title (feat. Robot)"
  [[ "${target%%* - }" == *','* ]] && {
    read -r -p "Artist seems to contain a comma, still split artists for feat. by comma? [y/N] " confirm_split
    [[ $confirm_split != "y" ]] && echo "not splitting artists" && unset split_featured
  }

  transcodefolder "$bitrate" "$target"
  searchAlbumArt
else
  # Exit if file doesn't exist
  echo "Cannot find file or folder \"$target\""
  exit 1
fi
