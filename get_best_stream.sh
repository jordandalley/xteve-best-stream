#!/bin/bash

# Enable caching for faster stream starts
cache=true
# specify directory to store cache items (allow overriding)
cache_dir="/home/threadfin/conf/cache"
# specify a maximum expiry for the cache item (in days)
cache_max=30
# ffmpeg and yt-dlp path
# manually configure if issues
yt_dlp_path=$(command -v yt-dlp)
ffmpeg_path=$(command -v ffmpeg)

construct_command() {
  yt_dlp_proxy=""
  ffmpeg_proxy=""

  if [[ -n "$http_proxy" ]]; then
    yt_dlp_proxy="--proxy \"$http_proxy\""
    ffmpeg_proxy="-http_proxy \"$http_proxy\""
  fi

  # get highest quality stream using yt-dlp
  getUrls=$(eval "$yt_dlp_path $yt_dlp_proxy --user-agent \"$user_agent\" -S br -f \"bv+ba/b\" -g \"$input\"")

  # check for google dai, and if exists in url set scte35 flag to true
  if [[ "$getUrls" == *"dai.google.com"* ]]; then
    scte35="true"
  fi

  # split each line into inputs for ffmpeg which include proxy (if applicable) and user agent strings
  constructInputs=$(echo "$getUrls" | awk -v ua="$user_agent" -v proxy="$ffmpeg_proxy" '{printf "%s -user_agent \"%s\" -i \"%s\" ", proxy, ua, $0}')

  if [[ "$scte35" == "true" ]]; then
    # is a scte35 or dai/ssai stream
    # construct ffmpeg command for these types of treams
    echo "$ffmpeg_path -y -hide_banner -loglevel quiet -analyzeduration 3000000 -probesize 10M -fflags +igndts -http_persistent 0 $constructInputs -c copy -f mpegts pipe:1"
  else
    # all other streams
    # construct the ffmpeg command for output to stdout
    echo "$ffmpeg_path -y -hide_banner -loglevel quiet -re -analyzeduration 3000000 -probesize 10M -fflags +discardcorrupt+genpts $constructInputs -async 1 -c copy -f mpegts pipe:1"
  fi
}

run_command() {
  # Run the ffmpeg command
  eval "$ffmpeg_command"
  # Capture the exit code of the ffmpeg command
  exit_code=$?

  # If the exit code is 1 (indicating failure)
  if [[ $exit_code -eq 1 ]]; then
    # Check if caching is enabled
    if [[ $cache == "true" ]]; then
      # If caching is enabled, purge the cache entry
      rm -f "$cache_file"
      # Regenerate a new ffmpeg command
      ffmpeg_command=$(construct_command)
      # Run the command again
      eval "$ffmpeg_command"
      # Capture the new exit code
      exit_code=$?
      # If the second attempt fails, return 1 (indicating failure)
      if [[ $exit_code -eq 1 ]]; then
        return 1
      fi
    fi
    # If caching is not enabled or the second attempt fails, return 1
    return 1
  fi
  # Return 0 if the command was successful
  return 0
}

check_cache() {
  if [ "$cache" == "true" ]; then
    # check if cache dir exists, and if not, create it
    mkdir -p "${cache_dir}"

    # expire cache elements older than specified cache_max time in days
    find "$cache_dir" -name "ffcmd-*" -mtime +"$cache_max" -exec rm -f {} +

    # create an md5 encoded string with the master input url
    input_md5=$(echo -n "$input" | md5sum | cut -d ' ' -f1)
    # create full path for file in cache
    cache_file="$cache_dir/ffcmd-$input_md5"

    # check if cache file still exists after expiring old cache objects
    if [ -f "$cache_file" ]; then
      # pull command from the cache
      ffmpeg_command=$(< "$cache_file")
      # check the ffmpeg command for only the first instance of 'exp=[0-9]{10}' which is an expiry timestamp. These are common in akamai streams.
      if [[ $ffmpeg_command =~ exp=([0-9]{10}) ]]; then
        # if there is a expiry string in the command, then extract it and check if it is expired
        if [[ ${BASH_REMATCH[1]} -lt $(date +%s) ]]; then
          # timestamp is expired, generate a new command and update cache file
          ffmpeg_command=$(construct_command)
          echo "$ffmpeg_command" > "$cache_file"
        fi
      fi
    else
      # no cache file exists, create a cache file
      ffmpeg_command=$(construct_command)
      echo "$ffmpeg_command" > "$cache_file"
    fi
  else
    # caching is not enabled, just construct the command
    ffmpeg_command=$(construct_command)
  fi
  run_command
}

usage() {
  echo "Usage: $0 -i <input> -user_agent <user-agent-string>"
  echo
  echo "Mandatory Arguments:"
  echo "  -i            Specify the input (e.g., URL or file)"
  echo "  -user_agent   Specify the User-Agent string"
  echo
  echo "Optional Arguments:"
  echo "  -http_proxy   Specify an http proxy to use (e.g., \"http://proxy.server.address:3128\")"
  echo
  echo "Example:"
  echo "  $0 -i \"https://url.to.stream/tvchannel.m3u8\" -user_agent \"Mozilla/5.0\""
  exit 1
}

# Capture arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i)
      if [[ -n "$2" && "$2" != -* ]]; then
        input="$2"
        shift 2
      else
        echo "Error: Missing value for -i argument."
        usage
      fi
      ;;
    -user_agent)
      if [[ -n "$2" && "$2" != -* ]]; then
        user_agent="$2"
        shift 2
      else
        echo "Error: Missing value for -user_agent argument."
        usage
      fi
      ;;
    -http_proxy)
      if [[ -n "$2" && "$2" != -* ]]; then
        http_proxy="$2"
        shift 2
      else
        http_proxy=""
        shift
      fi
      ;;
    -h|--help)
      usage
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "$input" || -z "$user_agent" ]]; then
  echo "Error: Missing required arguments."
  usage
fi

check_cache
