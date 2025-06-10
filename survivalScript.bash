#!/usr/bin/bash
#Turn a raspberrypi 5 into a survival hotspot
#Assuming you have power
#SUGGESTED - USB WLAN Adapter for increased range

##Perform System updates##
apt update && apt upgrade -y

#Install required dependencies
apt install -y git curl wget unzip nginx kiwix-tools python3 python3-pip

#Function makeDirs
#Filesystem prep - Create the appropriate directories
function makeDirs {
mkdir -p /srv/kiwix
mkdir -p /srv/maps
mkdir -p /srv/prepper
mkdir -p /srv/readygov
mkdir -p /srv/prepper/field-manuals
mkdir -p /srv/prepper/books
}

##Function downloadContent:
##Download all wiki packages required to do this
#This function is simple as fuck, it just downloads whats needed and puts
#It all in the right directory
#I am sure theres more but i dont feel like looking

function downloadContent {
wget -O /srv/kiwix/wikipedia_en_all_maxi.zim \
https://download.kiwix.org/zim/wikipedia/wikipedia_en_all_maxi_2024-05.zim

wget -O /srv/kiwix/wikihow_en_all_maxi.zim \
https://download.kiwix.org/zim/wikihow/wikihow_en_all_maxi_2024-05.zim

wget -O /srv/kiwix/wikimed_en_all_maxi.zim \
https://download.kiwix.org/zim/wikimed/wikimed_en_all_maxi_2024-05.zim

wget -O /srv/kiwix/wikibooks_en_all_maxi.zim \
https://download.kiwix.org/zim/wikibooks/wikibooks_en_all_maxi_2024-05.zim

wget -O /srv/kiwix/wikivoyage_en_all_maxi.zim \
https://download.kiwix.org/zim/wikivoyage/wikivoyage_en_all_maxi_2024-05.zim

wget -O /srv/prepper/field-manuals/FM21-76.pdf \
"https://ia601308.us.archive.org/1/items/Fm21-76/Fm21-76.pdf"

wget -O /srv/maps/north-america-latest.osm.pbf \
https://download.geofabrik.de/north-america-latest.osm.pbf
}


#Function readyGov:
#Install readyGov (Planning for disaster)

function readyGov {
httrack https://www.ready.gov/ -O /srv/readygov \
"+*.ready.gov/*" -v -n -%v -c8 -N100

##If the above doesnt work, uncomment this:
#wget --mirror --convert-links --adjust-extension --page-requisites --no-parent \
#-P /srv/readygov https://www.ready.gov/

}

#Download all of this stuff first, to get it ready:
makeDirs && downloadContent && readyGov

#Function : serveIt
#The fun part, serving it all
function serveIt {

# Run Kiwix server on port 8080
kiwix-serve --port=8080 /srv/kiwix/*.zim &
sleep 5

#Generate nginx config file:

# Example nginx config snippet:

cat <<EOF > /etc/nginx/sites-available/prepper
server {
    listen 80 default_server;
    server_name _;

    root /srv;

    index index.html index.htm;

    location /kiwix {
        proxy_pass http://localhost:8080;
    }

    location /readygov {
        alias /srv/readygov/;
    }

    location /prepper {
        alias /srv/prepper/;
    }

    location /maps {
        alias /srv/maps/;
    }
}
EOF

ln -s /etc/nginx/sites-available/prepper /etc/nginx/sites-enabled/prepper
rm /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx
}

#Function: buildInterface
#Need some way to view this shit, no?
function buildInterface {
cat <<EOF > /srv/index.html
<html>
<head><title>Offline Survival Pi</title></head>
<body>
<h1>Offline Survival Knowledge Server</h1>
<ul>
  <li><a href="/kiwix/">Offline Wikis (Wikipedia, Medical, How-to, Wikibooks)</a></li>
  <li><a href="/readygov/">FEMA Ready.gov Emergency Resources</a></li>
  <li><a href="/prepper/">Prepper Field Manuals & Books</a></li>
  <li><a href="/maps/">Offline Maps</a></li>
</ul>
</body>
</html>
EOF
}

serveIt	&& buildInterface

#Function makePiHotspot
#Uses dnsmasq to turn the pi insto a hotspot

function makePiHotspot {
apt install -y hostapd dnsmasq

if [ ! -f /etc/dnsmasq.conf.orig ]; then
   sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
fi

#Note, DHCP range is for clients connecting
    cat <<EOF | sudo tee /etc/dnsmasq.conf > /dev/null
interface=wlan0        # Use wlan0 interface only
dhcp-range=192.168.68.200,192.168.68.220,255.255.255.0,24h
domain-needed
bogus-priv
EOF
}

function setupSSID {

local SSID="$1"
local PASSPHRASE="$2"

if [ -z "$SSID" ] || [ -z "$PASSPHRASE" ]; then
   echo "SSID and password not set, fixing..but exiting now.."
   return 1
fi


cat <<EOF | sudo tee /etc/hostapd/hostapd.conf > /dev/null
interface=wlan0
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

cat <<EOF >> /etc/dhcpcd.conf
interface wlan0
    static ip_address=192.168.68.1/24
    nohook wpa_supplicant
EOF

#hostapd needs to know where to look, so tell it
sudo sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

#enable IPv4 Forwarding
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

}

setupSSID "Survival-Thing" "SomePassword" && makePiHotspot

sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq
