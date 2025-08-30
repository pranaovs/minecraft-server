#!/usr/bin/env sh

download_plugins() {
  trap clean INT TERM HUP

  echo "Downloading plugins"

  tmpdir=$(mktemp -d)

  while read -r url checksum; do

    filename="$(
      wget --content-disposition \
        -P "$tmpdir" \
        --trust-server-names \
        "$url" 2>&1 |
        grep "Saving to: " |
        grep -o "‘.*’" |
        sed "s/[‘’]//g"
    )"

    # Checksum verification
    if [ -n "$checksum" ]; then
      if ! echo "$checksum" "$filename" | sha256sum -c >/dev/null 2>&1; then
        rm -f "$tmpdir/$filename"
        echo "Checksum failed for $(basename "$filename"). Deleted"
      else
        cp -f "$filename" "./plugins/."
        echo "Installed plugin $(basename "$filename")"
      fi
    else
      echo "Checksum does not exist for $(basename "$filename")"
      cp -f "$filename" "./plugins/."
      echo "Installed plugin $(basename "$filename")"
    fi

  done <./plugins.txt

  trap - INT TERM HUP
}

clean() {
  echo "Cleaning"
  test -d "./plugins" && rm -vf ./plugins/*.jar
  rm -vf paper-*.jar
}

download_server() {
  trap clean INT TERM HUP

  echo "Downloading paper"

  filename="$(
    wget --content-disposition \
      --trust-server-names \
      "$(cut -d " " -f 1 <./server.txt)" 2>&1 |
      grep "Saving to: " |
      grep -o "‘.*’" |
      sed "s/[‘’]//g"
  )"

  echo "$(cut -d " " -f 2 <./server.txt)" "$filename" | sha256sum -c || {
    echo "Server checksum failed"
    rm -vf "$filename"
    exit 1
  }

  trap - INT TERM HUP

}

start_server() {

  set -- paper-*.jar
  # If server not downloaded
  if [ "$1" = "paper-*.jar" ]; then
    download_server
    download_plugins
  fi

  set -- paper-*.jar
  start_cmd="java -jar $1 --nogui"

  echo "Starting $1"

  if command -v tmux && [ -z "$TMUX" ]; then
    tmux new-session -As minecraft "$start_cmd"
  else
    $start_cmd
  fi
}

checkout_branch() {
  new_branch="world-$(date +%Y%m%d-%H%M%S)"

  git checkout -b "$new_branch" || {
    echo "Failed to create new branch $new_branch"
    exit 1
  }
}

help_menu() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -c          Clean environment"
  echo "  -i          Download server and plugins"
  echo "  -p          Download plugins"
  echo "  -h          Show help"
  echo
  echo "If no options are provided, the server will start."
}

# If no arguments given, start server
if [ $# -eq 0 ]; then

  [ "$(git branch --show-current)" = "main" ] && checkout_branch
  start_server
  exit 0
fi

# POSIX argument parsing
while [ $# -gt 0 ]; do
  case "$1" in
  -c)
    clean
    ;;
  -p)
    download_plugins
    ;;
  -h)
    help_menu
    exit 0
    ;;
  -b)
    checkout_branch
    exit 0
    ;;
  *)
    echo "Invalid option: $1" >&2
    help_menu
    exit 1
    ;;
  esac
  shift
done
