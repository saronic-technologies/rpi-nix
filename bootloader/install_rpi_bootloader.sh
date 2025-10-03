if test $# -ne 1; then
    echo "Usage: $0 DEFAULT-CONFIG"
    exit 1
fi

# This script is generated using the toplevel, so we only use this to distinguish
# our other configurations from the one we want to set as default, as this is just the
# same toplevel that we are using
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
BOOTLOADER_STAGING_DIRECTORY="$STAGING_DIRECTORY/bootloader";

OTHER_PATHS_FILENAME="other_configurations.txt"
OTHER_PATHS_STAGING="$BOOTLOADER_STAGING_DIRECTORY/$OTHER_PATHS_FILENAME"
OTHER_PATHS="$BOOT_DIRECTORY/$OTHER_PATHS_FILENAME"

# Add an entry to our "other" list, for reference
addEntry() {
    local name="$1"
    local path="$2"
    local shortSuffix="$3"

    # Path to our Nix configuration's init script, which is the
    # Nix stage 2 loader
    local stage2="$path/init"

    local entryTitle="$name - $shortSuffix"
    local stage2Call="exec $stage2"
    local bootloaderCopyCommands=""

    # Our newest configuration gets the new init script, while the rest
    # just have their init commands stored

    if [ "$path" != "$NEW_CONFIGURATION" ]; then
      # Extract our bootloader commands from switch-to-configuration
      local switchToConfigurationPath="$path/bin/switch-to-configuration"
      
      if [ -f "$switchToConfigurationPath" ]; then
        # Extract our path to our bootloader installer, using the "INSTALL_BOOTLOADER"
        # key
        local installBootloaderPath
        installBootloaderPath=$(awk -F"'" '/^export INSTALL_BOOTLOADER=/{print $2}' "$switchToConfigurationPath")

        if [ -f "$installBootloaderPath" ]; then
          # We have our bootloader path; find our delimeters and extract all text between
          # them
          bootloaderCopyCommands=$(
            awk '/@BOOTLOADER_COPY_COMMANDS_START@/{flag=1; next}
                /@BOOTLOADER_COPY_COMMANDS_END@/{flag=0}
                flag { print "# " $0 }' "$installBootloaderPath"
          )
        fi
      fi
    else
      local initScript

      initScript="$(
        echo "#!/bin/sh"
        echo "# $entryTitle"
        echo "# created by install_rpi_bootloader.sh"
        echo "$stage2Call"
      )"
      echo "$initScript" > "$INIT_STAGING"
      echo "# older configurations: $OTHER_PATHS" >> "$INIT_STAGING"
      chmod +x "$INIT_STAGING"
    fi

    # Append our content to our "other" file, for reference
    echo -e "# $entryTitle\n$bootloaderCopyCommands\n# $stage2Call\n\n" >> "$OTHER_PATHS_STAGING"
}

# When we want to extract our commands for previous generations incase we need to recover,
# we can just use sed on the switch-to-configuration file and extract them like that, instead
# of storing them on the toplevel explicitly.

copyBootloaderFiles() {
@BOOTLOADER_COPY_COMMANDS_START@
@BOOTLOADER_COPY_COMMANDS@
@BOOTLOADER_COPY_COMMANDS_END@
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
# !!! Should we do a hash check to see if we need to replace them?
# !!! I'm halfway between on this; it's not a large amount of data, and the
# !!! files are all stored with each configuration, so we don't have a risk of losing them
copyBootloaderFiles

# Replace our boot directory
mv "$BOOTLOADER_STAGING_DIRECTORY" "$BOOT_DIRECTORY"
mv "$INIT_STAGING" "$INIT"
