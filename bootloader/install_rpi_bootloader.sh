if test $# -ne 1; then
    echo "Usage: $0 DEFAULT-CONFIG"
    exit 1
fi

# This script is generated using the toplevel, so we only use this to distinguish
# our other configurations from the one we want to set as default
NEW_CONFIGURATION="$1"

INIT=/sbin/init
BOOT_DIRECTORY=/boot/firmware

[ "$(stat -f -c '%i' /)" = "$(stat -f -c '%i' /boot)" ] || {
  # see grub-menu-builder.sh
  echo "WARNING: /boot being on a different filesystem not supported by init-script-builder.sh"
}

# Create a staging directory, as we need to atomically update our boot partition, so
# we write what we need to staging and then move it over when we're done

STAGING_DIRECTORY=$(mktemp -d)

INIT_STAGING="$STAGING_DIRECTORY/init.tmp"
BOOTLOADER_STAGING_DIRECTORY="$TEMP_DIRECTORY/bootloader";
OTHER_PATHS_STAGING="$BOOTLOADER_STAGING_DIRECTORY/other_configurations.txt"

# Add an entry to $targetOther
addEntry() {
    local name="$1"
    local path="$2"
    # local shortSuffix="$3"

    local stage2="$path/init"

    content="$(
      echo "#!/bin/sh"
      echo "# $name"
      echo "# created by install_rpi_bootloader.sh"
      echo "exec $stage2"
    )"

    [ "$path" != "$NEW_CONFIGURATION" ] || {
      echo "$content" > "$INIT_STAGING"
      echo "# older configurations: $OTHER_PATHS_STAGING" >> "$INIT_STAGING"
      chmod +x "$INIT_STAGING"
    }

    echo -e "$content\n\n" >> "$OTHER_PATHS_STAGING"
}

copyBootloaderFiles() {
  @BOOTLOADER_COPY_COMMANDS@
}

# Make our bootloader staging area
mkdir -p "$BOOTLOADER_STAGING_DIRECTORY"

addEntry "@DISTRO_NAME@ - Default" "$NEW_CONFIGURATION" ""

# Add all generations of the system profile to the menu, in reverse
# (most recent to least recent) order.
for link in $( (ls -d "$NEW_CONFIGURATION/specialisation/*" ) | sort -n); do
    date=$(stat --printf="%y\n" "$link" | sed 's/\..*//')
    addEntry "@DISTRO_NAME@ - variation" "$link" ""
done

for generation in $(
    (cd /nix/var/nix/profiles && ls -d system-*-link) \
    | sed 's/system-\([0-9]\+\)-link/\1/' \
    | sort -n -r); do
    link="/nix/var/nix/profiles/system-$generation-link"
    date=$(stat --printf="%y\n" "$link" | sed 's/\..*//')
    if [ -d "$link/kernel" ]; then
      actualPath=$(readlink -f "$link/kernel")
      kernelDirectory=$(dirname "$actualPath")
      kernelVersion=$(cd "$kernelDirectory/lib/modules" && echo *)
      # kernelVersion=$(cd "$(dirname $(readlink -f $link/kernel))/lib/modules" && echo *)
      suffix="($date - $kernelVersion)"
    else
      suffix="($date)"
    fi
    addEntry "@DISTRO_NAME@ - Configuration $generation $suffix" "$link" "$generation ($date)"
done

# Copy our bootloader files
copyBootloaderFiles

# Replace our boot directory
mv "$BOOTLOADER_STAGING_DIRECTORY" "$BOOT_DIRECTORY"
mv "$INIT_STAGING" "$INIT"
