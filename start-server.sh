#!/usr/bin/env sh

clean_downloads() {
  echo "Cleaning"
  test -d "./plugins" && rm -vf ./plugins/*.jar
  rm -vf paper-*.jar
}

download_plugins() {
  trap clean_downloads INT TERM HUP

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

download_server() {
  trap clean_downloads INT TERM HUP

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

  if command -v tmux >/dev/null && [ -z "$TMUX" ]; then
    tmux new-session -As minecraft "$start_cmd"
  else
    $start_cmd
  fi
}

new_world() {
  echo "Creating new world"

  git checkout main || {
    echo "Failed to checkout main branch"
    exit 1
  }

  new_branch="world-$(date +%Y%m%d-%H%M%S)"

  git checkout -b "$new_branch" || {
    echo "Failed to create new branch $new_branch"
    exit 1
  }
}

save_world() {
  echo "Saving world"

  git add -A || {
    echo "Failed to stage changes"
    exit 1
  }

  git commit -m "World auto save at $(date +%Y%m%d-%H%M%S)" || {
    echo "Failed to commit changes"
  }

}

clean_world() {
  echo "Cleaning world"

  git reset --hard HEAD && git clean -fd

  clean_downloads
}

help_menu() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -n          Create new world (branch)"
  echo "  -s          Save current world (commit)"
  echo "  -p          Download plugins"
  echo "  -C          Clean world to last save (commit)"
  echo "  -h          Show help"
  echo
  echo "If no options are provided, the server will start."
}

# POSIX argument parsing
while [ $# -gt 0 ]; do
  case "$1" in
  -C)
    clean_world
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
  -n)
    save_world
    new_world
    ;;
  -s)
    save_world
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

if [ "$(git branch --show-current)" = "main" ]; then
  new_world
else
  save_world
fi

start_server
