#!/usr/bin/env bash
# cheetah
# transcoding tool

check_dependencies() {
  local dependency dependencies missing_dependencies

  # only require ssed if sed doesn't support case-insensitive matching
  if sed 's/foo/bar/i' /dev/null &>/dev/null; then
      _sed='sed'
      _sed_extended='sed -E'
  else
      _sed='ssed'
      _sed_extended='ssed -r'
  fi

  missing_dependencies=()
  dependencies=(
    flac
    id3v2
    lame
    mediainfo
    # metaflac is part of flac
    mktorrent
    rsync
    $_sed # $_sed or $_sed depeding on case support
  )

  for dependency in "${dependencies[@]}"; do
    if ! command -v "$dependency" &>/dev/null; then
      missing_dependencies+=("$dependency")
    fi
  done

  [[ ${#missing_dependencies[@]} -ne 0 ]] && {
    printf 'Missing dependencies: %s\n' "${missing_dependencies[*]}"
    echo "Please install them before using cheetah"
    exit
  }
}

get_info() {
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
        bitrate=$(regex_num_only "$CONTENT")
        ;;
    esac
  done < /tmp/cheetah.xml
}

detect_bitrate() {
  # reset all detected fields
  bitrate=""
  brtype="" # bit rate type: CBR/VBR
  encoding=""

  get_info "$1"

  [[ $encoding == "" ]] && encoding="_blank_"

  echo "\"$1\""
  echo "Bitrate: ${GREEN}$bitrate kbps${D}"
  echo "Mode: ${GREEN}$brmode${D}"
  echo "Encoding: ${GREEN}$encoding${D}"
  echo
  echo "$1 is a $fileformat file"
}

# Author: Teddy Skarin
# progress_bar currentState($1) and totalState($2)
# output: Progress: [########################################] 100%
progress_bar() {
  # process data
  local _progress=$(( 10#${1}*100/${2} ))
  local _done=$(( (${_progress}*4)/10 ))
  local _left=$(( 40-$_done ))

  # build progress_bar string lengths
  _done=$(printf "%${_done}s")
  _left=$(printf "%${_left}s")

  # build progress_bar strings and print the progress_bar line
  printf "\rProgress: [${_done// /#}${_left// /-}] ${_progress}%%  "
}

# transcode V0 /path/input.flac ~/outputfolder/
transcode() {
  local title artist album year track_number genre
  local main_artist feat_artist
  local output_file sanitised_title settings

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

  title="$(metaflac --show-tag=title "$file" | $_sed 's/[^=]*=//')"
  artist="$(metaflac --show-tag=artist "$file" | $_sed 's/[^=]*=//')"
  album="$(metaflac --show-tag=album "$file" | $_sed 's/[^=]*=//')"
  year="$(metaflac --show-tag=date "$file" | $_sed 's/[^=]*=//' | $_sed_extended 's/^([0-9]{4}).*$/\1/')" # ensure year is 4 digits
  track_number="$(metaflac --show-tag=tracknumber "$file" | $_sed 's/[^=]*=//')"
  genre="$(metaflac --show-tag=genre "$file" | $_sed 's/[^=]*=//')"

  # change track_number '2/11' to '2'
  track_number=$(echo "$track_number" | cut -f1 -d"/")

  # pad track number if not 2 digits
  [[ ${#track_number} == 1 ]] && track_number="0$track_number"

  # strip anything after second character
  [[ ${#track_number} != 2 ]] && track_number="${track_number:0:2}"

  # check bool, move featured artists into title (split by comma)
  [[ $split_featured && $artist == *','* ]] && {
    main_artist="${artist%%,*}"
    feat_artist="${artist#*,}"

    artist="$main_artist"

    # add features to title, and squash multiple spaces
    title="$(echo "$title (feat. $feat_artist)" | awk '{$1=$1;print}')"
  }

  # Replace illegal characters with dash
  sanitised_title="$(echo "$title" | $_sed 's/[?:;*\/]/-/g')"

  # Replace original filename with custom name
  output_file="$folder/$track_number $sanitised_title.mp3"

  if [[ -f "$output_file" ]]; then
    echo "File already exists: ${RED}$output_file${D}"
    exit 1
  else
    # shellcheck disable=SC2086 # $settings var is multiple flags, quotes are unfavorable
    flac -cds "$file" | lame -h --silent $settings --add-id3v2 --tt "$title" --ta "$artist" --tl "$album" --tv TPE2="$artist" --ty "$year" --tn "$track_number/$total_tracks" --tg "$genre" - "$output_file"
  fi
}

# transcode_folder V0 source
transcode_folder() {
  bitrate="$1"
  [[ -z "$bitrate" ]] && echo "${RED}Must specify bitrate [320/V0/etc]${D}" && exit 1

  cd "$2"

  album=${PWD##*/}
  in_path=$(pwd)
  out_path=$(echo "$in_path" | $_sed "s/FLAC/$bitrate/i")

  # append bitrate to folder if original folder omitted "FLAC", failing substitution
  [[ "$in_path" == "$out_path" ]] && out_path="$out_path [$bitrate]"

  total_tracks=$(ls -1qU *.flac | wc -l | awk '{print $1}')

  # ensure there are files to transcode
  [[ $total_tracks == 0 ]] && {
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

  echo "Transcoding ${RED}$total_tracks${D} FLACs in ${RED}$album${D} to MP3 $bitrate"
  counter=0
  for i in *.flac; do
    progress_bar $counter "$total_tracks"
    transcode "$bitrate" "$i" "$out_path"
    counter=$(( counter+1 ))
  done
  progress_bar $counter "$total_tracks" && echo

  rsync -a cover.* folder.* *.jpg "$out_path" 2>/dev/null

  # notify "Finished transcoding $album to MP3 $bitrate"
  echo "$bitrate transcode output to ${BLUE}$out_path${D}"
}

search_album_art() {
  # Remove illegal characters, encode spaces
  search="$(echo "$album $artist $year" | $_sed 's/ /+/g' | $_sed 's/[?:;*&\/\\]//g')"

  echo "Search google for cover art:"
  echo "https://google.com/search?safe=off&tbs=imgo:1,isz:lt,islt:qsvga&tbm=isch&q=$search"
}

# Read xml files
read_dom () {
  local IFS=\>
  read -r -d \< ENTITY CONTENT
}

# Regex remove any char not numeric
regex_num_only() {
  echo "$@" | $_sed 's/[^0-9]*//g'
}

# Execute main
# cheetah

# Colours
D=$'\e[37;49m'
BLUE=$'\e[34;49m'
GREEN=$'\e[32;49m'
RED=$'\e[31;49m'

# ensure dependencies are installed or exit
check_dependencies

target=${1%/} # strip trailing slash
split_featured=true

# Assume current folder if no target specified
[[ -z "$target" ]] && target="."

if [[ "$target" == "info" ]]; then
  # cheetah info "01 Song.flac"
  # Show tag info on the specified file
  target="$2"
  get_info "$target"

  if [[ "$fileformat" == "FLAC" ]]; then
    metaflac --list --block-number=2 "$target"
  elif [[ "$fileformat" == "MPEG Audio" ]]; then
    id3v2 -l "$target"
  else
    echo "$fileformat"
  fi

  echo
  detect_bitrate "$target"
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

  transcode_folder "$bitrate" "$target"
  search_album_art
else
  # Exit if file doesn't exist
  echo "Cannot find file or folder \"$target\""
  exit 1
fi
