#!/bin/sh
set -e

prompt_password() {
	printf "Enter password: "
	trap 'stty echo' INT
	stty -echo
	read PASSWORD
	stty echo
	printf "\n"
	PASSWORD="$(echo "$PASSWORD" | shasum | awk '{print $1}')"
}

random=$(tr -dc _A-Z-a-z-0-9 </dev/urandom | head -c10)

if [ "$1" = "new" ]; then
	if [ -z "$2" ]; then
		echo "Usage: $0 new <vault>"
		exit 1
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

	dd if=/dev/zero of="$vault" bs=1M count=32
	echo "$PASSWORD" | cryptsetup -q -d - luksFormat "$vault"

	echo "$PASSWORD" | sudo cryptsetup -q -d - luksOpen "$vault" "$ident"
	sudo mkfs.ext4 -Fq /dev/mapper/"$ident"
	sudo cryptsetup -q luksClose "$ident"
elif [ "$1" = "open" ]; then
	if [ -z "$2" ]; then
		echo "Usage: $0 open <vault>"
		exit 1
	fi

	if [ ! -f ./"$(basename "$2")" ]; then
		echo "You need to be in the same directory as the vault file"
		exit 1
	fi

	vault="$2"
	ident="$vault$random"
	newname=".$vault-$ident"

	prompt_password

	mv "$vault" "$newname"

	mkdir "$vault"
	echo "$PASSWORD" | sudo cryptsetup -q -d - luksOpen "$newname" "$ident"
	sudo mount /dev/mapper/"$ident" "$vault"
elif [ "$1" = "close" ]; then
	if [ -z "$2" ]; then
		echo "Usage: $0 close <vault>"
		exit 1
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
	sudo cryptsetup -q luksClose "$ident"
	rm -rf "$opened"
	mv "$vault" "$opened"
fi
