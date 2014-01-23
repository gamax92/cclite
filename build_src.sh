#!/bin/sh
if [ -f ./cclite-latest-beta.love ]; then
	read -p "Overwrite cclite-latest-beta.love [Y/N]: " replace
	if [ $replace != "Y" ] && [ $replace != "y" ]; then
		exit
	fi
	rm cclite-latest-beta.love
fi
cd src
zip -r -9 ../cclite-latest-beta.love *
cd ..
read -p "Press enter to continue . . . " dummyvar