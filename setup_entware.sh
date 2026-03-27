#!/bin/sh

# 1. Поиск пути к USB
USB_PATH=$(ls -d /mnt/usb-* 2>/dev/null | head -n 1)
ENT_DIR="$USB_PATH/opt"
LOG_FILE="/tmp/entware_install.log"
FINAL_LOG="$ENT_DIR/entware.log"
STARTUP_FILE="/data/startup_entware.sh"

# Улучшенная функция логирования: $1 - сообщение, $2 - тип (info/err/ok)
log() {
    local msg="$1"
    local type="$2"
    local timestamp=$(date '+%F %T')
    
    # Запись в файл (всегда)
    echo "[$timestamp] $msg" >> "$LOG_FILE"
    [ -d "$ENT_DIR" ] && echo "[$timestamp] $msg" >> "$FINAL_LOG"

    # Вывод в консоль (красиво)
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

    log "Создание папок на USB..." "info"
    mkdir -p "$ENT_DIR/tmp" || { log "Диск защищен от записи!" "err" ; exit 1; }

    log "Скачивание установщика (может занять время)..." "info"
    wget http://bin.entware.net/aarch64-k3.10/installer/generic.sh -O "$ENT_DIR/tmp/generic.sh" 2>>"$LOG_FILE"
    
    if [ ! -f "$ENT_DIR/tmp/generic.sh" ]; then
        log "Не удалось скачать файл. Проверьте интернет." "err"
        exit 1
    fi

    log "Запуск скрипта установки generic.sh..." "info"
    chmod +x "$ENT_DIR/tmp/generic.sh"
    sh "$ENT_DIR/tmp/generic.sh" >> "$LOG_FILE" 2>&1

    log "Настройка переменных окружения и обновление opkg..." "info"
    export PATH="/opt/bin:/opt/sbin:$PATH"
    /opt/bin/opkg update >> "$LOG_FILE" 2>&1

    log "Регистрация автозапуска в /data/ и UCI..." "info"
    cp "$0" "$STARTUP_FILE" && chmod +x "$STARTUP_FILE"
    
    uci -q delete firewall.entware
    uci set firewall.entware=include
    uci set firewall.entware.type='script'
    uci set firewall.entware.path="$STARTUP_FILE"
    uci set firewall.entware.enabled='1'
    uci commit firewall

    if ! grep -q '/opt/bin' /etc/profile; then
        log "Добавление путей в /etc/profile..." "info"
        cat >> /etc/profile <<-'EOF'
			# Entware (USB /opt)
			export PATH="/opt/bin:/opt/sbin:$PATH"
			export LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"
		EOF
    fi

    log "Entware полностью установлена!" "ok"
    echo "================================"
}

uninstall_entware() {
    echo "=== Запуск удаления Entware ==="
    
    log "Остановка активных сервисов..." "info"
    [ -x /opt/etc/init.d/rc.unslung ] && /opt/etc/init.d/rc.unslung stop >> "$LOG_FILE" 2>&1

    log "Размонтирование /opt..." "info"
    umount -l /opt 2>/dev/null

    log "Очистка системных записей автозапуска..." "info"
    uci -q delete firewall.entware
    uci commit firewall
    rm -f "$STARTUP_FILE"

    log "Удаление файлов с USB накопителя..." "info"
    rm -rf "$ENT_DIR"

    log "Entware полностью удалена." "ok"
    echo "================================"
}

run_services() {
    # Здесь логи в консоль не выводим (фоновый процесс), только в файл
    for i in $(seq 1 10); do
        [ -d "$ENT_DIR" ] && break
        sleep 2
    done

    if [ -d "$ENT_DIR" ]; then
        [ -d /opt ] || mkdir -p /opt
        mount | grep -q ' /opt ' || mount --bind "$ENT_DIR" /opt
        
        if mount | grep -q ' /opt '; then
            echo "[$(date '+%F %T')] [AUTOSTART] /opt mounted" >> "$FINAL_LOG"
            export PATH=/opt/bin:/opt/sbin:$PATH
            export LD_LIBRARY_PATH=/opt/lib
            
            if [ -x /opt/etc/init.d/rc.unslung ]; then
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
