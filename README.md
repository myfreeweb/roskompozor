# roskompozor

A Ruby script for Russian ISPs that fetches [the censorship list](https://github.com/zapret-info/z-i) using [the web service they are required to use](http://vigruzki.rkn.gov.ru/docs/description_for_operators_actual.pdf).

## Подготовка

(Подразумевается, что скрипт будет рабоать на UNIX-сервере, а сейчас электронная подпись используется на Windows)

### Сертификат и ключ

Сначала нужно получить сертификат компании и соответствующий приватный ключ в формате, с которым будет работать OpenSSL.

Экспортируем сертификат в PKCS#7 формате из встроенного менеджера сертификатов Windows, пусть это будет `exported.p7b`.

Вытаскиваем сертификат из файла:

```bash
$ openssl pkcs7 -in exported.p7b -inform der -print_certs > company.cert.pem
```

Редактируем `company.cert.pem`, убираем текстовые описания, чтобы оставался только сертификат (`-----BEGIN CERTIFICATE-----` и все, что дальше).

Копируем контейнер в криптопровайдере из USB-токена на диск, если контейнер не на диске.

Открываем контейнер в соответствующей демонстрации библиотеки [WebCrypto GOST](https://rudonick.github.io/crypto/) ([CryptoPro](https://rudonick.github.io/crypto/demo-cp-keys.html), [SignalCom](https://rudonick.github.io/crypto/demo-sc-keys.html), [ViPNet](https://rudonick.github.io/crypto/demo-vn-keys.html)):
Load Container file, вводим пароль, Export Key and Certificate, забираем текст из Private Key в текстовый файл (аккуратно! Приватный ключ в открытом виде!), назовем его `company.key.pem`.

Конвертируем его в DER и исправляем поле с названием алгоритма, в котором WebCrypto GOST ошибается:

```bash
$ openssl asn1parse -in company.key.pem -inform pem -out company.key.der
$ ruby fix_key_algorithm.rb company.key.der
$ srm company.key.pem company.key.der
$ mv company.key.der.fixed.der company.key.der
```

([srm](https://en.wikipedia.org/wiki/Srm_%28Unix%29) -- безопасное удаление файлов)

### OpenSSL

Теперь нужно установить OpenSSL с поддержкой ГОСТовых алгоритмов.

```bash
$ mkdir /opt/gost-ssl
$ wget https://www.openssl.org/source/openssl-1.0.2d.tar.gz
$ tar -xvf openssl-1.0.2d.tar.gz
$ cd openssl-1.0.2d
$ ./config shared zlib enable-rfc3779 --prefix=/opt/gost-ssl
$ make depend
$ make
$ make install
```

### Ruby

Ставим [Bundler](http://bundler.io), если его еще нет, и используем его для получения нужных библиотек:

```bash
$ gem install bundler
$ bundle install
```

## 3, 2, 1... Пуск

```bash
$ bundle exec ruby roskompozor.rb
```

Настройки (пути к ключу, сертификату, OpenSSL) можно менять через environment variables.

По умолчанию используется тестовый сервис, с настоящим запускать вот так:

```bash
$ WSDL_URL="http://vigruzki.rkn.gov.ru/services/OperatorRequest/?wsdl" bundle exec ruby roskompozor.rb
```

Ставим в cron с перенаправлением вывода в лог, читаем лог иногда :-)
