Инструкция по установке Entware нативно
____________________________________________________________________
Я упростил установку до нельзя, поэтому все, что вам нужно сделать: 
1. Убедиться, что флешка вставлена в роутер и работает
2. Подключиться по SSH к роутеру и вставить команду:
curl -L -k -s https://raw.githubusercontent.com/frogost/entware_xiaomi/main/setup_entware.sh -o /tmp/setup_entware.sh && chmod +x /tmp/setup_entware.sh && /tmp/setup_entware.sh install
3. После установки выйдите из SSH и зайдите снова.
4. Введите opkg update && opkg upgrade
5. Попробуйте поставить что-нибудь полезное, например: opkg install nano
____________________________________________________________________
Логи установки запишутся в файл: /tmp/entware_install.log (и удалятся после перезагрузки роутера)
Логи автозапуска будут записываться в файл: /mnt/usb-xxxxxx/opt/entware.log
Системная папка Entware после установки: /mnt/usb-xxxxxx/opt или просто /opt
Проверка установки Entware команда: /data/startup_entware.sh status
Удаление Entware команда: /data/startup_entware.sh uninstall
