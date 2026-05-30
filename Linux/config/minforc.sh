#!/usr/bin/env bash
# file: minforc.sh
# desc: Shared config for the media tools (imdbdump, imdbthumbgrab,
#       minfocreate). Place this in ~/scripts/lib/ (or ~/.config/).
#       Every value can also be overridden by an environment variable
#       of the same name.

# Get a free OMDb API key at: https://www.omdbapi.com/apikey.aspx
OMDB_API_KEY="${OMDB_API_KEY:-your_api_key_here}"

# Where minfocreate looks for the source video when none is given.
MINFO_VIDEODIR="${MINFO_VIDEODIR:-$HOME/Rip/done}"

# Output locations.
MINFO_NFODIR="${MINFO_NFODIR:-$HOME/Rip/nfo}"
MINFO_POSTERDIR="${MINFO_POSTERDIR:-$HOME/Rip/meta/posters}"
