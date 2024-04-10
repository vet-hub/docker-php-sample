# syntax=docker/dockerfile:1

# tutorial https://docs.docker.com/language/php/containerize/

# Comments are provided throughout this file to help you get started.
# If you need more help, visit the Dockerfile reference guide at
# https://docs.docker.com/go/dockerfile-reference/
# Want to help us make this template better? Share your feedback here: https://forms.gle/ybq9Krt8jtBL3iCk7

# tutorial https://docs.docker.com/language/php/develop/
################################################################################

# Create a stage for installing app dependencies defined in Composer.
# FROM composer:lts as deps


# Разделение deps на два этапа: prod-deps для pruduction dependencies и dev-deps для install development dependencies
# почему разделение: Composer не устанавливает зависимости разработки. Хотя этот небольшой образ хорош для производства, в нем отсутствуют инструменты и зависимости, которые могут вам понадобиться при разработке, и он не включает каталог tests
FROM composer:lts as prod-deps

WORKDIR /app

# If your composer.json file defines scripts that run during dependency installation and reference your application source files, uncomment the line below to copy all the files into this layer.
# Если ваш файл composer.json определяет scripts, которые запускаются во время установки зависимостей и ссылаются на исходные файлы вашего приложения, раскомментируйте строку ниже, чтобы скопировать все файлы для этих scripts в этот слой.
# COPY . .

# Download dependencies as a separate step to take advantage of Docker's caching. Leverage a bind mounts to composer.json and composer.lock to avoid having to copy them into this layer. Leverage a cache mount to /tmp/cache so that subsequent builds don't have to re-download packages.
# Загрузите зависимости как отдельный шаг, чтобы воспользоваться преимуществами кэширования Docker. Используйте привязку к композитору.json и композитору.lock, чтобы избежать необходимости копировать их в этот слой. Используйте монтирование кеша в /tmp/cache, чтобы при последующих сборках не приходилось повторно загружать пакеты.
RUN --mount=type=bind,source=composer.json,target=composer.json \
    --mount=type=bind,source=composer.lock,target=composer.lock \
    --mount=type=cache,target=/tmp/cache \
    composer install --no-dev --no-interaction


FROM composer:lts as dev-deps
WORKDIR /app
RUN --mount=type=bind,source=./composer.json,target=composer.json \
    --mount=type=bind,source=./composer.lock,target=composer.lock \
    --mount=type=cache,target=/tmp/cache \
    composer install --no-interaction

################################################################################

# Create a new stage for running the application that contains the minimal
# runtime dependencies for the application. This often uses a different base
# image from the install or build stage where the necessary files are copied
# from the install stage.
#
# Создайте новый stage для запуска приложения: FROM ..., содержащий минимальные зависимости времени выполнения приложения. При этом часто используется базовый образ, отличный от этапа install or build, в новый образ необходимые файлы могут копироваться из stage build or install. см ниже # Copy the app dependencies from the previous install stage.

# The example below uses the PHP Apache image as the foundation for running the app.
# By specifying the "8.2.4-apache" tag, it will also use whatever happens to be the
# most recent version of that tag when you build your Dockerfile.
# If reproducability is important, consider using a specific digest SHA, like
# php@sha256:99cede493dfd88720b610eb8077c8688d3cca50003d76d1d539b0efc8cca72b4.
#
# В приведенном ниже примере в качестве основы для запуска приложения используется образ PHP Apache. Указав тег «8.2.4-apache», он также будет использовать самую последнюю версию этого тега при создании Dockerfile. Если воспроизводимость важна, рассмотрите возможность использования специального дайджеста SHA, например
# php@sha256:99cede493dfd88720b610eb8077c8688d3cca50003d76d1d539b0efc8cca72b4.


# общая base stage
FROM php:8.2.4-apache as base
RUN docker-php-ext-install pdo pdo_mysql
COPY ./src /var/www/html

# Your PHP application may require additional PHP extensions to be installed
# manually. For detailed instructions for installing extensions can be found, see
# https://github.com/docker-library/docs/tree/master/php#how-to-install-more-php-extensions
# The following code blocks provide examples that you can edit and use.
# Для вашего PHP-приложения может потребоваться установка вручную дополнительных расширений PHP. Подробные инструкции по установке расширений можно найти, см.
# https://github.com/docker-library/docs/tree/master/php#how-to-install-more-php-extensions
# Следующие блоки кода содержат примеры, которые вы можете редактировать и использовать.
#
# Add core PHP extensions, see
# https://github.com/docker-library/docs/tree/master/php#php-core-extensions
# This example adds the apt packages for the 'gd' extension's dependencies and then
# installs the 'gd' extension. For additional tips on running apt-get, see
# https://docs.docker.com/go/dockerfile-aptget-best-practices/

# Добавьте основные расширения PHP, см.
# https://github.com/docker-library/docs/tree/master/php#php-core-extensions
# В этом примере добавляются пакеты apt для зависимостей расширения «gd», а затем устанавливается расширение «gd». Дополнительные советы по запуску apt-get см.
# https://docs.docker.com/go/dockerfile-aptget-best-practices/
# RUN apt-get update && apt-get install -y \
#     libfreetype-dev \
#     libjpeg62-turbo-dev \
#     libpng-dev \
# && rm -rf /var/lib/apt/lists/* \
#     && docker-php-ext-configure gd --with-freetype --with-jpeg \
#     && docker-php-ext-install -j$(nproc) gd
#
# Add PECL extensions, see
# https://github.com/docker-library/docs/tree/master/php#pecl-extensions
# This example adds the 'redis' and 'xdebug' extensions.
# RUN pecl install redis-5.3.7 \
#    && pecl install xdebug-3.2.1 \
#    && docker-php-ext-enable redis xdebug


# в процессе development нам понадобятся инструменты и зависимости для тестов, поэтому реорганизуем stages:
# new development stage
FROM base as development
COPY ./tests /var/www/html/tests
RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"
# copy the app dependencies from the previous stage dev-deps
COPY --from=dev-deps app/vendor/ /var/www/html/vendor

# запуск тестов при локальной разработке с помощью Compose:
# >docker compose run --build --rm server ./vendor/bin/phpunit tests/HelloWorldTest.php

# запуск тестов при сборке - новый этап тестирования (новый образ), на котором выполняются тесты: 
FROM development as test
WORKDIR /var/www/html
# PHPUnit устанавливается выше composer install в контейнер при сборке как зависимость описанная в composer.json "phpunit/phpunit": "^9.6"
RUN ./vendor/bin/phpunit tests/HelloWorldTest.php
# >docker build -t php-docker-image-test --progress plain --no-cache --target test .

# final stage to copy dependencies from the new prod-deps stage
FROM base as final
# Use the default production configuration for PHP runtime arguments, see
# Используйте production конфигурацию по умолчанию для аргументов PHP runtime, см.
# https://github.com/docker-library/docs/tree/master/php#configuration
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# copy the app dependencies from the previous stage prod-deps
COPY --from=prod-deps app/vendor/ /var/www/html/vendor

# Switch to a non-privileged user (defined in the base image) that the app will run under.
# See https://docs.docker.com/go/dockerfile-user-best-practices/
# в конфигурации Apache2 по умолчанию владелец файлов www-data
USER www-data
