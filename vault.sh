#!/bin/sh
set -e

prompt_password() {
	printf "Enter password: "
	trap 'stty echo' INT
	stty -echo
	read -r PASSWORD
	stty echo
	printf "\n"
	PASSWORD="$(echo "$PASSWORD" | shasum | awk '{print $1}')"
}

usage() {
	echo "Usage: vault <new|open|close|resize> <vault>"
	exit 1
}

luks_open() {
	echo "$PASSWORD" | sudo cryptsetup -q -d - luksOpen "$1" "$2"
}

luks_close() {
	sudo cryptsetup -q luksClose "$1"
}

random=$(tr -dc _A-Z-a-z-0-9 </dev/urandom | head -c10)

if [ "$1" = "new" ]; then
	if [ -z "$2" ]; then
		usage
	fi

	if [ -f "$2" ]; then
		echo "File already exists"
		exit 1
	fi

	touch "$2"

	if [ ! -f ./"$(basename "$2")" ]; then
		echo "You need to be in the same directory as the vault file"
		exit 1
	fi

	vault="$2"
	ident="$vault$random"

	prompt_password

	dd if=/dev/zero of="$vault" bs=1M count=32 >/dev/null 2>&1
	echo "$PASSWORD" | cryptsetup -q -d - luksFormat "$vault"

	luks_open "$vault" "$ident"
	sudo mkfs.ext4 -Fq /dev/mapper/"$ident"
	luks_close "$ident"
elif [ "$1" = "open" ]; then
	if [ -z "$2" ]; then
		usage
	fi

	base="$(basename "$2")"
	if [ ! -f ./"$base" ]; then
		echo "You need to be in the same directory as the vault file"
		exit 1
	fi

	if [ -d ./"$base" ]; then
		echo "There already exists a directory $base"
		exit 1
	fi

	vault="$2"
	ident="$vault$random"
	newname=".$vault-$ident"

	prompt_password

	mv "$vault" "$newname"

	luks_open "$newname" "$ident" || {
		mv "$newname" "$vault"
		exit 1
	}
	mkdir "$vault"
	sudo mount /dev/mapper/"$ident" "$vault"
	sudo chown "$USER" "$vault"
elif [ "$1" = "close" ]; then
	if [ -z "$2" ]; then
		usage
	fi

	base="$(basename "$2")"
	if [ ! -d ./"$base/" ]; then
		echo "You need to be in the same directory as the opened vault"
		exit 1
	fi

	opened="$base"
	candidates="$(find . -type f -name ".$opened-*" 2>/dev/null | cat)"

	if [ "$(echo "$candidates" | wc -l)" -gt 1 ]; then
		echo "Multiple vaults with the same name are opened"
		exit 1
	fi

	vault="$candidates"
	ident="$(echo "$vault" | cut -d- -f2)"

	sudo umount "$opened"
	luks_close "$ident"
	rm -rf "$opened"
	mv "$vault" "$opened"
elif [ "$1" = "resize" ]; then
	if [ -z "$2" ]; then
		usage
	fi

	if [ ! -f ./"$(basename "$2")" ]; then
		echo "You need to be in the same directory as the vault file"
		exit 1
	fi

	vault="$2"
	ident="$vault$random"

	cp "$vault" ".$ident.bak"

	current="$(ls -lh "$vault" | awk '{print $5}')"
	echo "Current: $current"
	printf "Expand by: "
	read -r increase

	# TODO: remove requirement for qemu-img
	# I tried using dd/truncate/etc but it didn't work..
	qemu-img resize -q -f raw "$vault" +"$increase"

	prompt_password

	luks_open "$vault" "$ident" || {
		mv ".$ident.bak" "$vault"
		exit 1
	}
	echo "$PASSWORD" | sudo cryptsetup -q -d - resize /dev/mapper/"$ident"
	sudo e2fsck -f /dev/mapper/"$ident" >/dev/null 2>&1
	sudo resize2fs /dev/mapper/"$ident" >/dev/null 2>&1
	luks_close "$ident"

	rm ".$ident.bak"
else
	usage
fi
