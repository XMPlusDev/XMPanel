#!/bin/bash
 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
info()   { echo -e "${BLUE}[i]${NC} $1"; }
error()  { echo -e "${RED}[✘]${NC} $1"; }

CONTAINERS=(
  npm
  ai
  ui
  phpmyadmin
  redis
  xmplus
  mariadbxmplus
)

IMAGES=(
  xmplusdev/xmplus-go:latest
  xmplusdev/xmplus-ui:latest
  mariadb:12.2
  redis:8.6-alpine
  phpmyadmin:latest
  nginxproxy/nginx-proxy:latest
  nginxproxy/acme-companion:latest
)

check_docker() {
  if ! command -v docker &>/dev/null; then
    error "Docker is not installed or not in PATH."
    exit 1
  fi
  if ! docker info &>/dev/null; then
    error "Docker daemon is not running."
    exit 1
  fi
}

# check root
[[ $EUID -ne 0 ]] && error "This script must be run with the root user！\n" && exit 1

remove_containers() {
  info "Processing containers..."
  for name in "${CONTAINERS[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
      # Stop if running
      if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        docker stop "$name" &>/dev/null
        warn "Stopped: $name"
      fi
      docker rm -f "$name" &>/dev/null
      log "Removed container: $name"
    else
      warn "Container not found, skipping: $name"
    fi
  done
}

remove_images() {
  info "Processing images..."
  for image in "${IMAGES[@]}"; do
    if docker image inspect "$image" &>/dev/null; then
      docker rmi -f "$image" &>/dev/null
      log "Removed image: $image"
    else
      warn "Image not found, skipping: $image"
    fi
  done
}

remove_dangling_images() {
  # Remove untagged (dangling) images
  info "Removing untagged (dangling) images..."
  dangling=$(docker images -qf "dangling=true")
  if [[ -n "$dangling" ]]; then
    echo "$dangling" | xargs docker rmi -f &>/dev/null
    log "Untagged images removed."
  else
    warn "No untagged images found, skipping."
  fi
}

check_status() {
	if [[ ! -f /etc/systemd/system/XMP.service ]]; then
		return 2
	fi
	
	STATUS=$(docker inspect --format='{{.State.Health.Status}}' xmplus_api 2>/dev/null || echo "not_found")
	if [ "$STATUS" = "healthy" ]; then
        return 0
    elif [ "$STATUS" = "unhealthy" ]; then
        return 1
    fi
}

check_install() {
	if [[ ! -f /etc/systemd/system/XMP.service ]]; then
		error "Panel is not installed. Please run the installer first"
		if [[ $# == 0 ]]; then
			before_show_menu
		fi
		return 1
	fi
}

api() {
	check_status
	if [[ $? == 0 ]]; then
		cd /home/XMPanel
		docker compose logs -f xmplus_api
	else
		error "Unable to tail API logs. Panel is not running"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

ui() {
	check_status
	if [[ $? == 0 ]]; then
		cd /home/XMPanel
		docker compose logs -f xmplus_ui
	else
		error "Unable to tail UI logs. Panel is not running"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

mariadb() {
	check_status
	if [[ $? == 0 ]]; then
		cd /home/XMPanel
		docker compose logs -f xmplus_mariadb
	else
		error "Unable to tail MariaDB logs. Panel is not running"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

redis() {
	check_status
	if [[ $? == 0 ]]; then
		cd /home/XMPanel
		docker compose logs -f xmplus_redis
	else
		error "Unable to tail Redis logs. Panel is not running"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

uninstall() {
	confirm "Are you sure you want to uninstall XMPlus Panel? " "n"
	if [[ $? != 0 ]]; then
		if [[ $# == 0 ]]; then
			show_menu
		fi
		return 0
	fi
	if [ -e "/etc/systemd/system/XMP.service" ]; then
		systemctl stop XMP
		systemctl disable XMP
		rm /etc/systemd/system/XMP.service -f
		systemctl daemon-reload
		systemctl reset-failed
	fi
	
	rm /home/XMPanel/ -rf
	rm -f /usr/bin/xmp
	
	#uninstall images and containers
	check_docker
	remove_containers
	remove_dangling_images
	remove_images

	echo ""
	log "Panel successfully disabled and removed"
	echo ""

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

start() {
	systemctl start XMP
	sleep 2
	check_status
	if [[ $? == 0 ]]; then
		log "Panel started successfully"
	else
		error "Panel failed to start. Please check the log information"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

stop() {
	systemctl stop XMP
	sleep 2
	check_status
	if [[ $? == 1 ]]; then
		log "Panel successfully stopped"
	else
		error "Panel failed to stop, probably because the stop time exceeded two seconds. Please check the log information"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

restart() {
	systemctl restart XMP
	sleep 2
	check_status
	if [[ $? == 0 ]]; then
		log "Panel restarted successfully."
	else
		error "Panel may have failed to start. Use 'xmp log' to check the log information"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

status() {
	systemctl status XMP --no-pager -l
	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

enable() {
	systemctl enable XMP
	if [[ $? == 0 ]]; then
		log "Auto-start panel on system boot enabled successfully"
	else
		error "Failed to enable panel auto-start on system boot"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

disable() {
	systemctl disable XMP
	if [[ $? == 0 ]]; then
		log "Panel auto-start on system boot disabled successfully"
	else
		error "Failed to disable panel auto-start on system boot"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

show_log() {
	journalctl -u XMP.service -e --no-pager -f
	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

update() {
	warn "Pulling latest Docker images..."
	
	if [[ -f /usr/bin/xmp ]]; then
	  rm -rf /usr/bin/xmp
	fi
	 
	curl -o /usr/bin/xmp -Ls https://raw.githubusercontent.com/XMPlusDev/XMPlanel/scripts/xmp.sh
	chmod +x /usr/bin/xmp
	
	cd /home/XMPanel
	docker compose pull
	if [[ $? == 0 ]]; then
		docker compose up -d --force-recreate
		remove_dangling_images
		log "Panel updated and restarted successfully"
	else
		error "Failed to pull latest images. Please check your network or image registry"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

config() {
	if [[ -f /home/XMPanel/.env ]]; then
		log "Current configuration (/home/XMPanel/.env):"
		echo "--------------------------------------------"
		cat /home/XMPanel/.env
		echo "--------------------------------------------"
	else
		error "Configuration file not found at /home/XMPanel/.env"
	fi

	if [[ $# == 0 ]]; then
		before_show_menu
	fi
}

confirm() {
	if [[ $# > 1 ]]; then
		echo && read -p "$1 [${2}]: " temp
		if [[ x"${temp}" == x"" ]]; then
			temp=${2}
		fi
	else
		echo && read -p "$1 [y/n]: " temp
	fi
	if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
		return 0
	else
		return 1
	fi
}

before_show_menu() {
	echo && echo -n -e "${YELLOW}Press enter to return to the main menu: ${NC}" && read temp
	show_menu
}

check_enabled() {
	temp=$(systemctl is-enabled XMP)
	if [[ x"${temp}" == x"enabled" ]]; then
		return 0
	else
		return 1
	fi
}

show_status() {
	check_status
	case $? in
		0)
			echo -e "Panel Status: ${GREEN}Running${NC}"
			show_enable_status
			;;
		1)
			echo -e "Panel Status: ${YELLOW}Not Running${NC}"
			show_enable_status
			;;
		2)
			echo -e "Panel Status: ${RED}Not Installed${NC}"
	esac
}

show_enable_status() {
	check_enabled
	if [[ $? == 0 ]]; then
		echo -e "Automatically start on boot: ${GREEN}Yes${NC}"
	else
		echo -e "Automatically start on boot: ${RED}No${NC}"
	fi
}

show_menu() {
	echo -e "
  ${GREEN}XMPlus Panel Management${NC}

————————————————
  ${GREEN}0.${NC} Show Configuration
  ${GREEN}1.${NC} Update Panel
  ${GREEN}2.${NC} Uninstall Panel
————————————————
  ${GREEN}3.${NC} Start Panel
  ${GREEN}4.${NC} Stop Panel
  ${GREEN}5.${NC} Restart Panel
  ${GREEN}6.${NC} View Panel Status
  ${GREEN}7.${NC} View Panel Log
————————————————
  ${GREEN}8.${NC} Enable Panel Auto-Start
  ${GREEN}9.${NC} Disable Panel Auto-Start
————————————————
  ${GREEN}10.${NC} View API Docker Logs
  ${GREEN}11.${NC} View UI Docker Logs
  ${GREEN}12.${NC} View MariaDB Docker Logs
  ${GREEN}13.${NC} View Redis Docker Logs
————————————————
 "
	show_status
	echo && read -p "Please enter selection [0-14]: " num

	case "${num}" in
		0) config
		;;
		1) check_install && update
		;;
		2) check_install && uninstall
		;;
		3) check_install && start
		;;
		4) check_install && stop
		;;
		5) check_install && restart
		;;
		6) check_install && status
		;;
		7) check_install && show_log
		;;
		8) check_install && enable
		;;
		9) check_install && disable
		;;
		10) check_install && api
		;;
		11) check_install && ui
		;;
		12) check_install && mariadb
		;;
		13) check_install && redis
		;;
		*) echo -e "${RED}Please enter the correct number [0-14]${NC}"
		;;
	esac
}

# Entry point — handle CLI args or show interactive menu
case "$1" in
	start)         check_install 1 && start 1 ;;
	stop)          check_install 1 && stop 1 ;;
	restart)       check_install 1 && restart 1 ;;
	status)        check_install 1 && status 1 ;;
	enable)        check_install 1 && enable 1 ;;
	disable)       check_install 1 && disable 1 ;;
	log)           check_install 1 && show_log 1 ;;
	update)        check_install 1 && update 1 ;;
	config)        config 1 ;;
	uninstall)     check_install 1 && uninstall 1 ;;
	api)           check_install 1 && api 1 ;;
	ui)            check_install 1 && ui 1 ;;
	redis)         check_install 1 && redis 1 ;;
	mariadb)       check_install 1 && mariadb 1 ;;
	*)             show_menu ;;
esac