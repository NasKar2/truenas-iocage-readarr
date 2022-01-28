#!/bin/sh
# Build an iocage jail under TrueNAS 12.3 with  Readarr
# https://github.com/NasKar2/sepapps-freenas-iocage

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

# Initialize defaults
JAIL_IP=""
JAIL_NAME=""
DEFAULT_GW_IP=""
INTERFACE=""
VNET=""
POOL_PATH=""
APPS_PATH=""
READARR_DATA=""
MEDIA_LOCATION=""
TORRENTS_LOCATION=""
USE_BASEJAIL="-b"

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/readarr-config
CONFIGS_PATH=$SCRIPTPATH/configs
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"

# Check for readarr-config and set configuration
if ! [ -e $SCRIPTPATH/readarr-config ]; then
  echo "$SCRIPTPATH/readarr-config must exist."
  exit 1
fi

# Check that necessary variables were set by readarr-config
if [ -z $JAIL_IP ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z $DEFAULT_GW_IP ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z $INTERFACE ]; then
  INTERFACE="vnet0"
  echo "INTERFACE defaulting to 'vnet0'"
fi
if [ -z $VNET ]; then
  VNET="on"
  echo "VNET defaulting to 'on'"
fi
if [ -z $POOL_PATH ]; then
  POOL_PATH="/mnt/$(iocage get -p)"
  echo "POOL_PATH defaulting to "$POOL_PATH
fi
if [ -z $APPS_PATH ]; then
  APPS_PATH="apps"
  echo "APPS_PATH defaulting to 'apps'"
fi
if [ -z $JAIL_NAME ]; then
  JAIL_NAME="readarr"
  echo "JAIL_NAME defaulting to 'readarr'"
fi

if [ -z $READARR_DATA ]; then
  READARR_DATA="readarr"
  echo "READARR_DATA defaulting to 'readarr'"
fi

if [ -z $MEDIA_LOCATION ]; then
  MEDIA_LOCATION="media"
  echo "MEDIA_LOCATION defaulting to 'media'"
fi

if [ -z $TORRENTS_LOCATION ]; then
  TORRENTS_LOCATION="torrents"
  echo "TORRENTS_LOCATION defaulting to 'torrents'"
fi

#
# Create Jail
echo '{"pkgs":["nano"]}' > /tmp/pkg.json
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" ${USE_BASEJAIL} allow_raw_sockets="1" allow_mlock="1" bpf="yes" boot="on"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

mkdir -p ${POOL_PATH}/${APPS_PATH}/${READARR_DATA}
mkdir -p ${POOL_PATH}/${MEDIA_LOCATION}/books
mkdir -p ${POOL_PATH}/${TORRENTS_LOCATION}
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${READARR_DATA}'"

chown -R media:media ${POOL_PATH}/${MEDIA_LOCATION}/books

readarr_config=${POOL_PATH}/${APPS_PATH}/${READARR_DATA}

iocage exec ${JAIL_NAME} mkdir -p /mnt/configs
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

# create dir in jail for mount points
iocage exec ${JAIL_NAME} mkdir -p /usr/ports
iocage exec ${JAIL_NAME} mkdir -p /var/db/portsnap
iocage exec ${JAIL_NAME} mkdir -p /config
iocage exec ${JAIL_NAME} mkdir -p /mnt/library
iocage exec ${JAIL_NAME} mkdir -p /mnt/configs
iocage exec ${JAIL_NAME} mkdir -p /mnt/torrents

#
# mount ports so they can be accessed in the jail
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/ports /usr/ports nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/db /var/db/portsnap nullfs rw 0 0

iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${readarr_config} /config nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${MEDIA_LOCATION}/books /mnt/library nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${TORRENTS_LOCATION} /mnt/torrents nullfs rw 0 0

iocage restart ${JAIL_NAME}

# add media user
iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /config -s /usr/bin/nologin"
  
# add media group to media user
#iocage exec ${JAIL_NAME} pw groupadd -n media -g 8675309
#iocage exec ${JAIL_NAME} pw groupmod media -m media
#iocage restart ${JAIL_NAME} 

#
# Install Readarr
iocage exec ${JAIL_NAME} "fetch https://github.com/Thefrank/freebsd-port-sooners/releases/download/20210613/radarrv3-3.2.2.5080.txz"
iocage exec ${JAIL_NAME} "pkg install -y radarrv3-3.2.2.5080.txz"
iocage exec ${JAIL_NAME} "fetch "https://readarr.servarr.com/v1/update/healthchecks/updatefile?os=bsd&arch=x64&runtime=netcore" -o /readarr.tar.gz"
iocage exec ${JAIL_NAME} "mkdir /usr/local/share/readarr"
iocage exec ${JAIL_NAME} "tar -xf /readarr.tar.gz -C /usr/local/share/readarr"
iocage exec ${JAIL_NAME} "rm /usr/local/etc/rc.d/radarr"

iocage exec ${JAIL_NAME} chown -R media:media /usr/local/share/readarr /config
iocage exec ${JAIL_NAME} -- mkdir /usr/local/etc/rc.d
iocage exec ${JAIL_NAME} cp -f /mnt/configs/readarr /usr/local/etc/rc.d/radarr
iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/readarr
#iocage exec ${JAIL_NAME} sed -i '' "s/radarrdata/${RADARR_DATA}/" /usr/local/etc/rc.d/radarr
iocage exec ${JAIL_NAME} sysrc readarr_enable="YES"
iocage exec ${JAIL_NAME} sysrc readarr_user="media"
iocage exec ${JAIL_NAME} sysrc readarr_group="media"
iocage exec ${JAIL_NAME} sysrc readarr_data_dir="/config"
iocage exec ${JAIL_NAME} service readarr start
echo "Radarr installed"

#
# Make pkg upgrade get the latest repo
#iocage exec ${JAIL_NAME} mkdir -p /usr/local/etc/pkg/repos/
#iocage exec ${JAIL_NAME} cp -f /mnt/configs/FreeBSD.conf /usr/local/etc/pkg/repos/FreeBSD.conf

#
# Upgrade to the lastest repo
#iocage exec ${JAIL_NAME} pkg upgrade -y
#iocage restart ${JAIL_NAME}


#
# remove /mnt/configs as no longer needed
#iocage fstab -r ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0

# Make media owner of data directories
#chown -R media:media ${POOL_PATH}/${MEDIA_LOCATION}
#chown -R media:media ${POOL_PATH}/${TORRENTS_LOCATION}

echo
echo "Readarr should be available at http://${JAIL_IP}:8787"
