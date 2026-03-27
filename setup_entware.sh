#!/bin/sh

# Поиск пути к USB
USB_PATH=$(ls -d /mnt/usb-* 2>/dev/null | head -n 1)
ENT_DIR="$USB_PATH/opt"
LOG_FILE="/tmp/entware_install.log"
FINAL_LOG="$ENT_DIR/entware.log"
STARTUP_FILE="/data/startup_entware.sh"

log() {
    local msg="$1"
    local type="$2"
    local timestamp=$(date '+%F %T')
    
    echo "[$timestamp] $msg" >> "$LOG_FILE"
    [ -d "$ENT_DIR" ] && echo "[$timestamp] $msg" >> "$FINAL_LOG"

    case "$type" in
        "info") echo " -> $msg" ;;
        "err")  echo "[!] ОШИБКА: $msg" ;;
        "ok")   echo "[+] УСПЕХ: $msg" ;;
        *)      echo "$msg" ;;
    esac
}

install_entware() {
    echo "=== Запуск установки Entware ==="
    
    if [ -z "$USB_PATH" ]; then
        log "USB накопитель не найден в /mnt/" "err"
        exit 1
    fi
    log "Используем накопитель: $USB_PATH" "info"
	
	mkdir -p "$ENT_DIR" || { log "Диск защищен от записи!" "err" ; exit 1; }
	
    log "Подготовка точки монтирования /opt..." "info"
    [ -d /opt ] || mkdir -p /opt
    
    if mount | grep -q ' /opt '; then
        log "/opt уже смонтирован. Если это старая установка, удалите её командой uninstall." "err"
        exit 1
    fi
	
    mount --bind "$ENT_DIR" /opt
    if ! mount | grep -q ' /opt '; then
        log "Критическая ошибка: не удалось смонтировать /opt!" "err"
        exit 1
    fi
	
	log "Создание временной папки" "info"
    mkdir -p /opt/tmp
	
    log "Скачивание установщика..." "info"
    curl -L -k -s http://bin.entware.net/aarch64-k3.10/installer/generic.sh -o /opt/tmp/generic.sh
    
    if [ ! -f /opt/tmp/generic.sh ]; then
        log "Не удалось скачать файл. Проверьте интернет." "err"
        exit 1
    fi
	
    log "Запуск скрипта установки generic.sh (подождите)..." "info"
    chmod +x /opt/tmp/generic.sh
    sh /opt/tmp/generic.sh >> "$LOG_FILE" 2>&1
	
	log "Настройка переменных окружения" "info"
    if ! grep -q "/opt/bin" /etc/profile; then
            LOCAL_CURRENT_PATH=$(grep "^export PATH=" /etc/profile | cut -d'"' -f2)
            
            if [ -z "$LOCAL_CURRENT_PATH" ]; then
                echo 'export PATH="/opt/bin:/opt/sbin:$PATH"' >> /etc/profile
            else
                NEW_PATH="/opt/bin:/opt/sbin:$LOCAL_CURRENT_PATH"
                sed -i "s|^export PATH=.*|export PATH=\"$NEW_PATH\"|" /etc/profile
            fi

            if ! grep -q "LD_LIBRARY_PATH" /etc/profile; then
                echo 'export LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"' >> /etc/profile
            fi
    fi
    export PATH="/opt/bin:/opt/sbin:$PATH"
    export LD_LIBRARY_PATH="/opt/lib"
	
	log "Обновление opkg..." "info"
    /opt/bin/opkg update >> "$LOG_FILE" 2>&1

    log "Регистрация автозапуска в /data/ и Firewall..." "info"
    cp "$0" "$STARTUP_FILE" && chmod +x "$STARTUP_FILE"
    
    uci -q delete firewall.entware
    uci set firewall.entware=include
    uci set firewall.entware.type='script'
    uci set firewall.entware.path="$STARTUP_FILE"
    uci set firewall.entware.enabled='1'
    uci commit firewall

    log "Entware полностью установлена!" "ok"
    echo "================================"
}

uninstall_entware() {
    echo "=== Запуск удаления Entware ==="
    [ -x /opt/etc/init.d/rc.unslung ] && /opt/etc/init.d/rc.unslung stop >> "$LOG_FILE" 2>&1
    umount -l /opt 2>/dev/null
    uci -q delete firewall.entware
    uci commit firewall
    rm -f "$STARTUP_FILE"
    rm -rf "$ENT_DIR"
    log "Entware полностью удалена." "ok"
    echo "================================"
}

run_services() {
    for i in $(seq 1 10); do
        [ -d "$ENT_DIR" ] && break
        sleep 2
    done

    if [ -d "$ENT_DIR" ]; then
        [ -d /opt ] || mkdir -p /opt
        mount | grep -q ' /opt ' || mount --bind "$ENT_DIR" /opt

        if ! grep -q "/opt/bin" /etc/profile; then
            LOCAL_CURRENT_PATH=$(grep "^export PATH=" /etc/profile | cut -d'"' -f2)
            
            if [ -z "$LOCAL_CURRENT_PATH" ]; then
                echo 'export PATH="/opt/bin:/opt/sbin:$PATH"' >> /etc/profile
            else
                NEW_PATH="/opt/bin:/opt/sbin:$LOCAL_CURRENT_PATH"
                sed -i "s|^export PATH=.*|export PATH=\"$NEW_PATH\"|" /etc/profile
            fi

            if ! grep -q "LD_LIBRARY_PATH" /etc/profile; then
                echo 'export LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"' >> /etc/profile
            fi
        fi

        if mount | grep -q ' /opt '; then
            export PATH="/opt/bin:/opt/sbin:$PATH"
            export LD_LIBRARY_PATH="/opt/lib"
            
            if [ -x /opt/etc/init.d/rc.unslung ]; then
                echo "[$(date '+%F %T')] [AUTOSTART] Starting services..." >> "$FINAL_LOG"
                /opt/etc/init.d/rc.unslung start >> "$FINAL_LOG" 2>&1
            fi
        fi
    fi
}

case "$1" in
    install)
        install_entware
        ;;
    uninstall)
        uninstall_entware
        ;;
    status)
        echo "--- Статус ---"
        mount | grep /opt || echo "/opt не смонтирован"
        [ -d /opt/bin ] && echo "Бинарники: OK" || echo "Бинарники: отсутствуют"
        ;;
    *)
        run_services &
        ;;
esac
